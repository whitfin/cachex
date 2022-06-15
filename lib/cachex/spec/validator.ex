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
                  Cachex.Spec.limit |
                  Cachex.Spec.warmer

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
    do: nillable?(default, &is_positive_integer/1)
          and nillable?(interval, &is_positive_integer/1)
          and is_boolean(lazy)

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
  def valid?(:hook, hook(module: module, name: name)),
    do: behaviour?(module, Cachex.Hook)
          and is_boolean(module.async?())
          and nillable?(name, &(is_atom(&1) or is_pid(&1)))
          and nillable?(module.timeout(), &is_positive_integer/1)
          and (enum?(module.actions(), &is_atom/1) or module.actions() == :all)
          and enum?(module.provisions(), &is_atom/1)
          and module.type() in [ :post, :pre ]

  # Validates a hooks specification record.
  #
  # This will just validate that every hook inside the pre/post hooks
  # is a valid hook instance. This is done using the valid?/1 clause
  # for a base hook record, rather than reimplementing here.
  def valid?(:hooks, hooks(pre: pre, post: post)),
    do: is_list(pre)
          and is_list(post)
          and enum?(pre ++ post, &valid?(:hook, &1))

  # Validates a limit specification record.
  #
  # This has to validate all fields in the record, with the size being a nillable integer,
  # the policy being a valid module, the reclaim space being a valid float between 0 and 1,
  # and a valid keyword list as the options.
  def valid?(:limit, limit(size: size, policy: policy, reclaim: reclaim, options: options)),
    do: module?(policy)
          and nillable?(size, &is_positive_integer/1)
          and is_number(reclaim)
          and reclaim > 0
          and reclaim <= 1
          and Keyword.keyword?(options)

  # Validates a warmer specification record.
  #
  # This will validate that the provided module correctly implements
  # the behaviour of `Cachex.Warmer` via function checking.
  def valid?(:warmer, warmer(module: module)),
    do: behaviour?(module, Cachex.Warmer)
          and { :interval, 0 } in module.__info__(:functions)
          and { :execute,  1 } in module.__info__(:functions)

  def valid?(:purge, purge(include_result_data: include_result_data)),
    do: is_boolean(include_result_data)

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
      { :behaviour, [ behaviour ] } in module.__info__(:attributes)
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
