defmodule Cachex.Spec.Validator do
  @moduledoc """
  Validation module for records defined in the specification.

  This module just exposes runtime validation functions for records defined
  in the spec; records themselves only determine keys and structure but cannot
  enforce type (that I know of) without additional runtime validations.

  This shouldn't be used outside of the library, but it can be if required.
  """
  import Cachex.Spec

  # internal spec to refer to each record type
  @type record ::
          Cachex.Spec.command()
          | Cachex.Spec.entry()
          | Cachex.Spec.expiration()
          | Cachex.Spec.fallback()
          | Cachex.Spec.hook()
          | Cachex.Spec.hooks()
          | Cachex.Spec.limit()
          | Cachex.Spec.warmer()

  ##############
  # Public API #
  ##############

  @doc """
  Validates a specification record type.

  This will provide runtime validation of types and values contained inside
  the specification records. Although records provide key validation, they
  don't expose much coverage of the provided values.

  This will delegate each record type to a customized validation function.
  """
  @spec valid?(atom, record) :: boolean

  # Validates a command specification record.
  #
  # The only requirements here are that the action have an arity of
  # 1, and the type be a valid read/write atom.
  def valid?(:command, command(type: type, execute: execute)),
    do: type in [:read, :write] and is_function(execute, 1)

  # Validates an entry specification record.
  #
  # This only has to validate the touch time and ttl values inside a record,
  # as the key and value can be of any type (including nil). The touch time
  # and ttl values must be integers if set, and the ttl value can be nil.
  def valid?(:entry, entry(touched: touched, ttl: ttl)),
    do: is_positive_integer(touched) and nillable?(ttl, &is_positive_integer/1)

  # Validates an expiration specification record.
  #
  # This has to validate the default/interval values as being a nillable integers,
  # and the lazy value has to be a boolean value (which can not be nil).
  def valid?(:expiration, expiration(default: def, interval: int, lazy: lazy)) do
    current = nillable?(def, &is_positive_integer/1)
    current = current and nillable?(int, &is_positive_integer/1)
    current = current and is_boolean(lazy)
    current
  end

  # Validates a fallback specification record.
  #
  # At this point it just needs to verify that the default value is a valid
  # function. We can only support functions with arity 1 or 2.
  def valid?(:fallback, fallback(default: default)),
    do: nillable?(default, &(is_function(&1, 1) or is_function(&1, 2)))

  # Validates a hook specification record.
  #
  # This validation will ensure the following:
  #
  # 1. The async value is a boolean
  # 2. The module provided is a valid module atom
  # 3. The provided options is a keyword list
  # 4. The provide value is a valid list
  # 5. The timeout value is a nillable integer
  # 6. The type value is either :pre or :post
  #
  # It might be that this is too strict for basic validation, but seeing
  # as the cache creation requires valid hooks it seems to make sense to
  # be this strict at this point.
  #
  # Side note: dodging the formatter here, sorry...
  def valid?(:hook, hook(module: module, name: name)) do
    current = behaviour?(module, Cachex.Hook)

    current = current and is_boolean(module.async?())
    current = current and nillable?(name, &(is_atom(&1) or is_pid(&1)))
    current = current and nillable?(module.timeout(), &is_positive_integer/1)

    current =
      current and
        (enum?(module.actions(), &is_atom/1) or module.actions() == :all)

    current = current and enum?(module.provisions(), &is_atom/1)
    current = current and module.type() in [:post, :pre]

    current
  end

  # Validates a hooks specification record.
  #
  # This will just validate that every hook inside the pre/post hooks
  # is a valid hook instance. This is done using the valid?/1 clause
  # for a base hook record, rather than reimplementing here.
  def valid?(:hooks, hooks(pre: pre, post: post)) do
    current = is_list(pre)
    current = current and is_list(post)
    current = current and enum?(pre ++ post, &valid?(:hook, &1))
    current
  end

  # Validates a limit specification record.
  #
  # This has to validate all fields in the record, with the size being a nillable integer,
  # the policy being a valid module, the reclaim space being a valid float between 0 and 1,
  # and a valid keyword list as the options.
  def valid?(:limit, limit() = limit) do
    limit(size: size, policy: policy, reclaim: reclaim, options: options) =
      limit

    current = module?(policy)
    current = current and nillable?(size, &is_positive_integer/1)
    current = current and is_number(reclaim)
    current = current and reclaim > 0
    current = current and reclaim <= 1
    current = current and Keyword.keyword?(options)
    current
  end

  # Validates a warmer specification record.
  #
  # This will validate that the provided module correctly implements
  # the behaviour of `Cachex.Warmer` via function checking.
  def valid?(:warmer, warmer(module: module)) do
    current = behaviour?(module, Cachex.Warmer)
    current = current and {:interval, 0} in module.__info__(:functions)
    current = current and {:execute, 1} in module.__info__(:functions)
    current
  end

  # Catch-all for invalid records.
  def valid?(_tag, _val),
    do: false

  ###############
  # Private API #
  ###############

  @doc false
  # Determines if a module implements a behaviour.
  defp behaviour?(module, behaviour) do
    unsafe?(fn ->
      {:behaviour, [behaviour]} in module.__info__(:attributes)
    end)
  end

  @doc false
  # Determines if the provided value is an enum.
  defp enum?(enum, condition),
    do: unsafe?(fn -> Enum.all?(enum, condition) end)

  @doc false
  # Determines if the provided value is a valid module.
  #
  # This is done by attempting to retrieve the module info using
  # the __info__/1 macro only available to valid Elixir modules.
  defp module?(module),
    do: unsafe?(fn -> !!module.__info__(:module) end)

  @doc false
  # Determines if a condition is truthy.
  #
  # This will catch any errors and return false.
  defp unsafe?(condition) do
    condition.()
  rescue
    _ -> false
  end
end
