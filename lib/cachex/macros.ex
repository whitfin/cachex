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
        def unquote(:handle_call)({ unquote(func_name), unquote_splicing(args) }, _, unquote(state))
        when unquote(guards) do
          unquote(body)
        end
      else
        def unquote(:handle_call)({ unquote(func_name), unquote_splicing(args) }, _, unquote(state)) do
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
        def unquote(:handle_cast)({ unquote(func_name), unquote_splicing(args) }, unquote(state))
        when unquote(guards) do
          unquote(body)
        end
      else
        def unquote(:handle_cast)({ unquote(func_name), unquote_splicing(args) }, unquote(state)) do
          unquote(body)
        end
      end
    end
  end

  defmacro deft(args, do: body) do
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

  def raise_result(res) do
    case res do
      { :ok, result } -> result
      { :error, err } -> raise err
    end
  end

  defp gen_unsafe(name) do
    to_string(name) <> "!"
    |> String.to_atom
  end

  defp parse_args(args) do
    case args do
      { :when, _, [ { func_name, ctx, args }, guards ] } ->
        { args, func_name, ctx, guards }
      { func_name, ctx, args } ->
        { args, func_name, ctx, nil }
    end
  end

end
