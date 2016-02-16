defmodule Cachex.Macros do
  @moduledoc false
  # Provides a number of Macros to make it more convenient to create both of the
  # GenServer functions (handle_call/handle_cast). It also provides a shortcut
  # to creating 'cache' methods which check if the GenServer exists, to avoid
  # failing out in a messy way.
  #
  # This module is gross, but it's compile time so I'm not going to spend too
  # much time in here.

  defmacro defcall(args, do: body) do
    { args, func_name, ctx, guards } = parse_args(args)

    args = args || []
    state = { :state, ctx, nil }

    quote do
      if unquote(guards != nil) do
        def handle_call({ unquote(func_name), unquote_splicing(args) }, _, unquote(state))
        when unquote(guards) do
          unquote(body)
        end
      else
        def handle_call({ unquote(func_name), unquote_splicing(args) }, _, unquote(state)) do
          unquote(body)
        end
      end
    end
  end

  defmacro defcast(args, do: body) do
    { args, func_name, ctx, guards } = parse_args(args)

    args = args || []
    state = { :state, ctx, nil }

    quote do
      if unquote(guards != nil) do
        def handle_cast({ unquote(func_name), unquote_splicing(args) }, unquote(state))
        when unquote(guards) do
          unquote(body)
        end
      else
        def handle_cast({ unquote(func_name), unquote_splicing(args) }, unquote(state)) do
          unquote(body)
        end
      end
    end
  end

  defmacro definfo(args, do: body) do
    { _args, func_name, ctx, guards } = parse_args(args)

    state = { :state, ctx, nil }

    quote do
      if unquote(guards != nil) do
        def handle_info(unquote(func_name), unquote(state))
        when unquote(guards) do
          unquote(body)
        end
      else
        def handle_info(unquote(func_name), unquote(state)) do
          unquote(body)
        end
      end
    end
  end

  defmacro defcheck(args, do: body) do
    { args, func_name, _ctx, guards } = parse_args(args)

    body = quote do
      cache = unquote(hd(args))
      if not is_atom(cache) or GenServer.whereis(cache) == nil do
        { :error, "Invalid cache name provided, got: #{inspect cache}" }
      else
        unquote(body)
      end
    end

    args = args || []

    quote do
      if unquote(guards != nil) do
        def unquote(func_name)(unquote_splicing(args))
        when unquote(guards) do
          unquote(body)
        end

        @doc false
        def unquote(gen_unsafe(func_name))(unquote_splicing(args))
        when unquote(guards) do
          raise_result(unquote(func_name)(unquote_splicing(args)))
        end
      else
        def unquote(func_name)(unquote_splicing(args)) do
          unquote(body)
        end

        @doc false
        def unquote(gen_unsafe(func_name))(unquote_splicing(args)) do
          raise_result(unquote(func_name)(unquote_splicing(args)))
        end
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
      :ok -> value
      :error -> raise value
    end
  end

  @doc """
  Lazy wrapper for creating an :error tuple.
  """
  def error(value), do: { :error, value }

  @doc """
  Lazy wrapper for creating an :ok tuple.
  """
  def ok(value), do: { :ok, value }

  @doc """
  Lazy wrapper for creating a :noreply tuple.
  """
  def noreply(value), do: { :noreply, value }

  @doc """
  Lazy wrapper for creating a :reply tuple.
  """
  def reply(value, state), do: { :reply, value, state}

  # converts an atom name to an unsafe version,
  # by adding a trailing `!` to the name
  defp gen_unsafe(name) do
    to_string(name) <> "!"
    |> String.to_atom
  end

  # coerces a macro with/without guards to the same tuple
  # so that it can be used safely regardless of what is passed
  defp parse_args(args) do
    case args do
      { :when, _, [ { func_name, ctx, args }, guards ] } ->
        { args, func_name, ctx, guards }
      { func_name, ctx, args } ->
        { args, func_name, ctx, nil }
    end
  end

end
