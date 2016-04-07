defmodule Cachex.Macros.Boilerplate do
  @moduledoc false
  # Provides shorthand wrappers to a Cachex action, by verifying that the provided
  # cache exists before executing an action. If the cache does not exist, an error
  # tuple will be returned. This is just convenience instead of having to check in
  # every interface function. In addition, we also generate an "unsafe" version of
  # each function. Unsafe functions will throw any errors, and return raw results.

  # alias the parent module
  alias Cachex.ExecutionError
  alias Cachex.Macros

  @doc """
  Defines both a safe and unsafe version of an interface function, the unsafe
  version simply unwrapping (hence `defwrap`) the results of the safe version.
  """
  defmacro defwrap(head, do: body) do
    explicit_head = gen_unsafe(head)
    { func_name, arguments } = Macros.name_and_args(head)
    sanitized_args = Macros.trim_defaults(arguments)

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
    scary_name = to_string(name) <> "!" |> String.to_atom
    put_elem(head, 0, scary_name)
  end

end
