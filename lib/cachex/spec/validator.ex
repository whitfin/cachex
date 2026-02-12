defmodule Cachex.Spec.Validator do
  @moduledoc false
  # Validation module for records defined in the specification.
  #
  # This module just exposes runtime validation functions for records defined
  # in the spec; records themselves only determine keys and structure but cannot
  # enforce type (that I know of) without additional runtime validations.
  #
  # This shouldn't be used outside of the library, but it can be if required.
  import Cachex.Spec

  # internal spec to refer to each record type
  @type cache_record ::
          Cachex.Spec.command()
          | Cachex.Spec.entry()
          | Cachex.Spec.expiration()
          | Cachex.Spec.hook()
          | Cachex.Spec.hooks()
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
  @spec valid?(atom, cache_record) :: boolean

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
  def valid?(:entry, entry(modified: modified, expiration: exp)),
    do: is_positive_integer(modified) and nillable?(exp, &is_positive_integer/1)

  # Validates an expiration specification record.
  #
  # This has to validate the default/interval values as being a nillable integers,
  # and the lazy value has to be a boolean value (which can not be nil).
  def valid?(:expiration, expiration(default: def, interval: int, lazy: lazy)) do
    check1 = nillable?(def, &is_positive_integer/1)
    check2 = check1 and nillable?(int, &is_positive_integer/1)
    check3 = check2 and is_boolean(lazy)
    check3
  end

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
    check1 = behaviour?(module, Cachex.Hook)

    check2 = check1 and is_boolean(module.async?())
    check3 = check2 and nillable?(name, &(is_atom(&1) or is_pid(&1)))
    check4 = check3 and nillable?(module.timeout(), &is_positive_integer/1)

    action = check4 and module.actions()
    check5 = check4 and (enum?(action, &is_atom/1) or action == :all)

    check6 = check5 and enum?(module.provisions(), &is_atom/1)
    check7 = check6 and module.type() in Cachex.Hook.types()

    check7
  end

  # Validates a hooks specification record.
  #
  # This will just validate that every hook inside the pre/post hooks
  # is a valid hook instance. This is done using the valid?/1 clause
  # for a base hook record, rather than reimplementing here.
  def valid?(:hooks, hooks(pre: pre, post: post)) do
    check1 = is_list(pre)
    check2 = check1 and is_list(post)
    check3 = check2 and enum?(pre ++ post, &valid?(:hook, &1))
    check3
  end

  # Validates a router specification record.
  #
  # This will validate the correctly implemented `Cachex.Router` behaviour
  # and confirm that the provided options are a keyword list.
  def valid?(:router, router() = router) do
    router(options: options, module: module) = router

    check1 = behaviour?(module, Cachex.Router)
    check2 = check1 and {:init, 2} in module.__info__(:functions)
    check3 = check2 and {:nodes, 1} in module.__info__(:functions)
    check4 = check3 and {:route, 2} in module.__info__(:functions)
    check5 = check4 and Keyword.keyword?(options)
    check5
  end

  # Validates a warmer specification record.
  #
  # This will validate that the provided module correctly implements the
  # behaviour of `Cachex.Warmer` via function checking.
  def valid?(:warmer, warmer() = warmer) do
    warmer(module: module, name: name, interval: interval, required: required) =
      warmer

    check1 = behaviour?(module, Cachex.Warmer)
    check2 = check1 and nillable?(interval, &is_positive_integer/1)
    check3 = check2 and {:execute, 1} in module.__info__(:functions)
    check4 = check3 and nillable?(name, &(is_atom(&1) or is_pid(&1)))
    check5 = check4 and is_boolean(required)
    check5
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
  # Determines if a condition is truthy.
  #
  # This will catch any errors and return false.
  defp unsafe?(condition) do
    condition.()
  rescue
    _ -> false
  end
end
