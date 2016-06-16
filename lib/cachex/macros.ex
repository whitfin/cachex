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
  alias Cachex.ExecutionError
  alias Cachex.Util

  @doc """
  Fetches the name and arguments from a function head and returns them inside a
  tuple.
  """
  def name_and_args(head) do
    head
    |> short_head
    |> Macro.decompose_call
  end

  @doc """
  Trim all defaults from a set of arguments.

  This is requried in case we want to pass arguments through to another function.
  """
  def trim_defaults(args) do
    Enum.map(args, fn(arg) ->
      case elem(arg, 0) do
        :\\ ->
          arg
          |> Util.last_of_tuple
          |> List.first
        _at ->
          arg
      end
    end)
  end

  @doc """
  Defines both a safe and unsafe version of an interface function, the unsafe
  version simply unwrapping (hence `defwrap`) the results of the safe version.
  """
  defmacro defwrap(head, do: body) do
    { func_name, arguments } = name_and_args(head)
    explicit_head  = gen_unsafe(head)
    sanitized_args = trim_defaults(arguments)

    quote do
      def unquote(head) do
        unquote(body)
      end

      @doc false
      def unquote(explicit_head) do
        case apply(Cachex, unquote(func_name), [unquote_splicing(sanitized_args)]) do
          { :error, value } when is_binary(value) ->
            raise ExecutionError, message: value
          { _state, value } ->
            value
        end
      end
    end
  end

  # allow the "use" syntax
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

  # Converts various function input to an unsafe version by adding a trailing
  # "!" to the function name.
  defp gen_unsafe({ :when, ctx, [head | tail] }) do
    scary_head = gen_unsafe(head)
    { :when, ctx, [scary_head|tail]}
  end
  defp gen_unsafe(head) do
    { name, _, _ } = head
    scary_name = Util.atom_append(name, "!")
    put_elem(head, 0, scary_name)
  end

  # We use this to normalize functions with/without guards
  defp short_head({ :when, _, [head | _] }), do: head
  defp short_head(head), do: head

end
