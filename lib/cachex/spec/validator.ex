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
  @type record :: Cachex.Spec.command |
                  Cachex.Spec.entry |
                  Cachex.Spec.expiration |
                  Cachex.Spec.fallback |
                  Cachex.Spec.hook |
                  Cachex.Spec.hooks |
                  Cachex.Spec.limit

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
    do: type in [ :read, :write ] and is_function(execute, 1)

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
  def valid?(:expiration, expiration(default: default, interval: interval, lazy: lazy)),
    do: nillable?(default, &is_positive_integer/1) and
        nillable?(interval, &is_positive_integer/1) and
        is_boolean(lazy)

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
  def valid?(:hook, hook(module: module, name: name)) do
    # unpack the extra properties we need to validate
    type = module.type()
    async = module.async?()
    actions = module.actions()
    timeout = module.timeout()
    provisions = module.provisions()

    # run the rest of the basic validations
    with true <- is_boolean(async),
         true <- nillable?(name, &(is_atom(&1) or is_pid(&1))),
         true <- nillable?(timeout, &is_positive_integer/1),
         true <- enum?(actions, &is_atom/1) or actions == :all,
         true <- enum?(provisions, &is_atom/1),
     do: (type in [ :post, :pre ])
  rescue
    _ -> false
  end

  # Validates a hooks specification record.
  #
  # This will just validate that every hook inside the pre/post hooks
  # is a valid hook instance. This is done using the valid?/1 clause
  # for a base hook record, rather than reimplementing here.
  def valid?(:hooks, hooks(pre: pre, post: post)),
    do: is_list(pre) and
        is_list(post) and
        enum?(pre ++ post, &valid?(:hook, &1))

  # Validates a limit specification record.
  #
  # This has to validate all fields in the record, with the size being a nillable integer,
  # the policy being a valid module, the reclaim space being a valid float between 0 and 1,
  # and a valid keyword list as the options.
  def valid?(:limit, limit(size: size, policy: policy, reclaim: reclaim, options: options)) do
    with true <- module?(policy),
         true <- nillable?(size, &is_positive_integer/1),
         true <- (is_number(reclaim) and reclaim > 0 and reclaim <= 1),
     do: Keyword.keyword?(options)
  rescue
    _ -> false
  end

  # Catch-all for invalid records.
  def valid?(_tag, _val),
    do: false

  ###############
  # Private API #
  ###############

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
