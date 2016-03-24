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
  alias Cachex.Util

  @doc """
  This is gross, but very convenient. It will basically define a function for the
  main Cachex module, and it short-circuits if the specified GenServer can not be
  found. In addition, it builds up a `!` version of the function to return values
  or throw errors explicity.
  """
  defmacro defcheck(head, do: body) do
    explicit_head = gen_unsafe(head)
    { func_name, arguments } = Macros.name_and_args(head)

    args_list =
      arguments
      |> Macro.prewalk([], fn(x, acc) ->
          case x do
            { key, _, _ } when key != :\\ ->
              { x, [key|acc] }
            _other ->
              { x, acc }
          end
        end)
      |> Util.last_of_tuple
      |> Enum.reverse

    quote do
      def unquote(head) do
        if not is_atom(var!(cache)) or GenServer.whereis(var!(cache)) == nil do
          { :error, "Invalid cache name provided, got: #{inspect var!(cache)}" }
        else
          unquote(body)
        end
      end

      @doc false
      def unquote(explicit_head) do
        args = binding()
        fun_args = Enum.map(unquote(args_list), &(args[&1]))
        raise_result(apply(Cachex, unquote(func_name), fun_args))
      end
    end
  end

  # allow the "use" syntax
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Neat little guy you can use to wrap the result of a function call returning
  an :ok/:error tuple to return just the result or throw the error. This is used
  when autogenerating `!` functions.

  ## Examples

      iex> Cachex.Macros.raise_result({ :ok, "value" })
      "value"

      iex> Cachex.Macros.raise_result({ :error, "value" })
      ** (RuntimeError) value

  """
  def raise_result({ status, value }) do
    cond do
      status == :error and is_binary(value) ->
        raise ExecutionError, message: value
      true -> value
    end
  end
  def raise_result(value), do: value

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
