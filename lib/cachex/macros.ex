defmodule Cachex.Macros do
  @moduledoc false
  # Provides a number of Macro utilities to make it more convenient to write new
  # Macros. This module is a parent of various submodules which provide Macros
  # for specific uses (to avoid bloating requires and imports). I'm pretty new
  # to Macros so if anything in here (or in submodules) can be done more efficiently,
  # feel free to suggest.
  #
  # The main offering here is the `defwrap` macro which provides shorthand wrappers
  # to a Cachex action, by generating an "unsafe" version of each function. Unsafe
  # functions will throw any errors, and return raw results.

  # add various aliases
  alias Cachex.Errors
  alias Cachex.ExecutionError
  alias Cachex.Util

  @doc """
  Trim all defaults from a set of arguments.
  """
  @spec trim_defaults(Macro.t) :: Macro.t
  def trim_defaults(arguments) do
    Enum.map(arguments, fn
      ({ :\\, _, [ arg | _ ] }) -> arg
      (arg) -> arg
    end)
  end

  @doc """
  Retrieves the name, arguments and optional guards for a definition.
  """
  @spec unpack_head(Macro.t) :: { atom, Macro.t, Macro.t | nil }
  def unpack_head({ :when, _, [ { name, _, arguments } | [ condition ] ] }),
    do: { name, arguments, condition }
  def unpack_head({ name, _, arguments }),
    do: { name, arguments, nil }

  @doc """
  Defines both a safe and unsafe version of an interface function, the unsafe
  version simply unwrapping the results of the safe version.
  """
  defmacro defwrap(head, do: body) do
    { name, arguments, _condition } = unpack_head(head)

    explicit_name  = Util.atom_append(name, "!")
    sanitized_args = trim_defaults(arguments)

    quote do
      def unquote(head) do
        unquote(body)
      end

      @doc false
      def unquote(explicit_name)(unquote_splicing(arguments)) do
        case unquote(name)(unquote_splicing(sanitized_args)) do
          { :error, value } when is_atom(value) ->
            raise ExecutionError, message: Errors.long_form(value)
          { :error, value } when is_binary(value) ->
            raise ExecutionError, message: value
          { _state, value } ->
            value
        end
      end
    end
  end
end
