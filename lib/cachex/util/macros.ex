defmodule Cachex.Util.Macros do
  @moduledoc false
  # Provides a number of Macros to make it more convenient to create both of the
  # GenServer functions (handle_call/handle_cast). It also provides a shortcut
  # to creating 'cache' methods which check if the GenServer exists, to avoid
  # failing out in a messy way.
  #
  # This module is gross, but it's compile time so I'm not going to spend too
  # much time in here.

  defmacro defcall(head, do: body) do
    { func_name, args } = name_and_args(head)

    quote do
      def handle_call({ unquote(func_name), unquote_splicing(args) }, _, var!(state)) do
        unquote(body)
      end
    end
  end

  defmacro defcast(head, do: body) do
    { func_name, args } = name_and_args(head)

    quote do
      def handle_cast({ unquote(func_name), unquote_splicing(args) }, var!(state)) do
        unquote(body)
      end
    end
  end

  defmacro defcheck(head, do: body) do
    explicit_head = gen_unsafe(head)
    { func_name, arguments } = name_and_args(head)

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
      |> get_last_of_tuple
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

  defmacro definfo(head, do: body) do
    { func_name, _ } = name_and_args(head)

    quote do
      def handle_info(unquote(func_name), var!(state)) do
        unquote(body)
      end
    end
  end

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
    case status do
      :error -> raise value
      _other -> value
    end
  end

  # converts an when body function to an unsafe version,
  # by adding a trailing `!` to the name
  defp gen_unsafe({:when, ctx, [head | tail]}) do
    scary_head = gen_unsafe(head)
    { :when, ctx, [scary_head|tail]}
  end

  # converts an normal function to an unsafe version,
  # by adding a trailing `!` to the name
  defp gen_unsafe(head) do
    { name, _, _ } = head
    scary_name = to_string(name) <> "!" |> String.to_atom
    put_elem(head, 0, scary_name)
  end

  # plucks the last value from a tuple
  defp get_last_of_tuple(tuple) do
    tuple
    |> elem(tuple_size(tuple) - 1)
  end

  # fetches the name and arguments of a function with guards
  defp name_and_args(head) do
    head
    |> short_head
    |> Macro.decompose_call
  end

  # fetches the name and arguments of a function without guards
  defp short_head({:when, _, [head | _]}), do: head
  defp short_head(head), do: head

end
