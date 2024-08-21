defmodule Cachex.Options do
  @moduledoc """
  Binding module to parse options into a cache record.

  This interim module is required to normalize the options passed to a
  cache at startup into a well formed record instance, allowing the rest
  of the codebase to make assumptions about what types of data are being
  dealt with.
  """
  import Cachex.Spec
  import Cachex.Errors

  # add some aliases
  alias Cachex.Spec
  alias Spec.Validator

  # option parser order
  @option_parsers [
    :name,
    :nodes,
    :limit,
    :hooks,
    :router,
    :ordered,
    :commands,
    :fallback,
    :compressed,
    :expiration,
    :transactions,
    :warmers
  ]

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves a conditional option from a Keyword List.

  If the value satisfies the condition provided, it will be returned. Otherwise
  the default value provided is returned instead. Used for basic validations.
  """
  @spec get(Keyword.t(), atom, (any -> boolean), any) :: any
  def get(options, key, condition, default \\ nil) do
    transform(options, key, fn val ->
      try do
        (condition.(val) && val) || default
      rescue
        _ -> default
      end
    end)
  end

  @doc """
  Parses a list of cache options into a cache record.

  This will validate any options and error on anything we don't understand. The
  advantage of binding into a cache instance is that we can blindly use it in
  other areas of the library without needing to validate. As such, this code can
  easily become a little messy - but that's ok!
  """
  @spec parse(atom, Keyword.t()) :: {:ok, Spec.cache()} | {:error, atom}
  def parse(name, options) when is_list(options) do
    # iterate all option parsers and accumulate a cache record
    parsed =
      Enum.reduce_while(@option_parsers, name, fn type, state ->
        case parse_type(type, state, options) do
          cache() = new_state ->
            {:cont, new_state}

          error ->
            {:halt, error}
        end
      end)

    # wrap for compatibility
    with cache() <- parsed do
      {:ok, parsed}
    end
  end

  @doc """
  Transforms and returns an option inside a Keyword List.
  """
  @spec transform(Keyword.t(), atom, (any -> any)) :: any
  def transform(options, key, transformer) do
    options
    |> Keyword.get(key)
    |> transformer.()
  end

  ###############
  # Private API #
  ###############

  # Parses out any custom commands to be used for custom invocations.
  #
  # We delegate most of the parsing to the Commands module; here we just check
  # that we have a Keyword List to work with, and that there are not duplicate
  # command entries (we want to keep the first to match a typical Keyword behaviour).
  defp parse_type(:commands, cache, options) do
    commands =
      transform(options, :commands, fn
        # map parsing is allowed
        map when is_map(map) -> map
        # keyword list parsing is allowed
        list when is_list(list) -> list
        # missing is fine
        nil -> []
        # anything else, nope!
        _invalid -> nil
      end)

    case commands do
      nil ->
        error(:invalid_command)

      cmds ->
        validated =
          Enum.all?(cmds, fn
            {_name, command} ->
              Validator.valid?(:command, command)

            _invalid_elements ->
              false
          end)

        case validated do
          false ->
            error(:invalid_command)

          true ->
            cmds_to_set =
              cmds
              |> Enum.reverse()
              |> Enum.into(%{})

            cache(cache, commands: cmds_to_set)
        end
    end
  end

  # Configures a cache based on compression flags.
  #
  # This will simply configure the `:compressed` field in the cache
  # record and return the modified record with the flag attached.
  defp parse_type(:compressed, cache, options),
    do:
      cache(cache,
        compressed: get(options, :compressed, &is_boolean/1, false)
      )

  # Configures an expiration options record for a cache.
  #
  # We don't allow any shorthands here because there's no logical
  # default to use. Therefore an expiration must be provided, otherwise
  # it'll fail validation and return an error to the caller.
  defp parse_type(:expiration, cache, options) do
    expiration =
      transform(options, :expiration, fn
        # provided expiration, woohoo!
        expiration() = expiration ->
          expiration

        # unset so default
        nil ->
          expiration()

        # anything else, no thanks!
        _invalid ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:expiration, expiration) do
      false -> error(:invalid_expiration)
      true -> cache(cache, expiration: expiration)
    end
  end

  # Sets up any cache-wide fallback behaviour.
  #
  # This will allow the shorthanding of a function to act as a default
  # fallback implementation; otherwise the provided value must be a
  # fallback record which is run through the specification validation.
  defp parse_type(:fallback, cache, options) do
    fallback =
      transform(options, :fallback, fn
        # provided fallback is great!
        fallback() = fallback ->
          fallback

        # allow shorthand of a function
        fun when is_function(fun) ->
          fallback(default: fun)

        # unset so default
        nil ->
          fallback()

        # anything else, no thanks!
        _invalid ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:fallback, fallback) do
      false -> error(:invalid_fallback)
      true -> cache(cache, fallback: fallback)
    end
  end

  # Configures any hooks to be enabled for the cache.
  #
  # In addition to the hooks already provided, this will also deal with the
  # notion of statistics hooks and limits, as they can both define hooks.
  defp parse_type(:hooks, cache(name: name, limit: limit) = cache, options) do
    hooks =
      Enum.concat([
        # stats hook generation
        case !!options[:stats] do
          false ->
            []

          true ->
            [
              hook(
                module: Cachex.Stats,
                name: name(name, :stats)
              )
            ]
        end,

        # limit hook generation
        case limit do
          limit(size: nil) ->
            []

          limit(policy: policy) ->
            apply(policy, :hooks, [limit])
        end,

        # provided hooks lists
        options
        |> Keyword.get(:hooks, [])
        |> List.wrap()
      ])

    # validation and division into a hooks record
    case validated?(hooks, :hook) do
      false ->
        error(:invalid_hook)

      true ->
        type = Enum.group_by(hooks, &hook(&1, :module).type())

        pre = Map.get(type, :pre, [])
        post = Map.get(type, :post, [])

        cache(cache, hooks: hooks(pre: pre, post: post))
    end
  end

  # Sets up any provided limit structures.
  #
  # This will allow shorthanding of a numeric value to act as a size
  # to bound the cache to. This will provide defaults for all other
  # fields in the limit structure.
  defp parse_type(:limit, cache, options) do
    limit =
      case Keyword.get(options, :limit) do
        limit() = limit -> limit
        size -> limit(size: size)
      end

    case Validator.valid?(:limit, limit) do
      false -> error(:invalid_limit)
      true -> cache(cache, limit: limit)
    end
  end

  # Creates a base cache record from a cache name.
  #
  # This is separated out just to allow being part of the parse pipeline
  # rather than having to special cache the parsing of the name.
  defp parse_type(:name, name, _options),
    do: cache(name: name)

  # Configures any nodes assigned to the cache.
  #
  # This will enforce a non-empty list of nodes, containing at least
  # the current local node. The list will be deduplicated, and sorted
  # to ensure a deterministic ordering across nodes.
  defp parse_type(:nodes, cache, options) do
    nodes =
      options
      |> Keyword.get(:nodes, [])
      |> Enum.concat([node()])
      |> Enum.uniq()
      |> Enum.sort()

    valid =
      nodes
      |> List.delete(node())
      |> Enum.all?(&Node.connect/1)

    case valid do
      # coveralls-ignore-start
      false ->
        error(:invalid_nodes)

      true ->
        cache(cache, nodes: nodes)
        # coveralls-ignore-stop
    end
  end

  # Configures a cache based on ordering flags.
  #
  # This will simply configure the `:ordered` field in the cache
  # record and return the modified record with the flag attached.
  defp parse_type(:ordered, cache, options),
    do:
      cache(cache,
        ordered: get(options, :ordered, &is_boolean/1, false)
      )

  # Configures a cache based on router flags.
  #
  # This allows a user to provide a custom router for distributed
  # caches, with the default being set to a default router record.
  defp parse_type(:router, cache() = cache, options) do
    router =
      transform(options, :router, fn
        # provided full record, woohoo!
        router() = router ->
          router

        # unset so default
        nil ->
          router()

        # shorthand router name
        mod when is_atom(mod) ->
          router(module: mod)

        # anything else, no thanks!
        _invalid ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:router, router) do
      false -> error(:invalid_router)
      true -> cache(cache, router: router)
    end
  end

  # Configures a cache based on transaction flags.
  #
  # This will simply configure the `:transactions` field in the cache
  # record and return the modified record with the flag attached.
  defp parse_type(:transactions, cache, options),
    do:
      cache(cache,
        transactions: get(options, :transactions, &is_boolean/1, false)
      )

  # Configures any warmers assigned to the cache.
  #
  # This will return a list of warmer records to be associated to the
  # cache at startup in the incubator service. All warmer records are
  # passed through validation beforehand in order to ensure correctness.
  defp parse_type(:warmers, cache, options) do
    # pull warmers
    warmers =
      options
      |> Keyword.get(:warmers, [])
      |> List.wrap()

    # validation of all warmer records
    case validated?(warmers, :warmer) do
      false -> error(:invalid_warmer)
      true -> cache(cache, warmers: warmers)
    end
  end

  # Shorthand validation of a record type.
  #
  # This just iterates and ensures all elements in the provided enum
  # are validated using the specification validation for the given type.
  defp validated?(enum, type),
    do: Enum.all?(enum, &Validator.valid?(type, &1))
end
