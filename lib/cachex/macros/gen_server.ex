defmodule Cachex.Macros.GenServer do
  @moduledoc false
  # Provides a number of Macros to make it more convenient to create any of the
  # GenServer functions (handle_call/handle_cast/handle_info). This is purely for
  # shorthand convenience and doesn't really provide anything too special.

  # alias the parent module
  alias Cachex.Macros
  alias Cachex.Util

  @doc """
  Generates a simple delegate binding for GenServer methods. This is in case the
  raw function is provided in the module and it should be accessible via the server
  as well.
  """
  defmacro gen_delegate(head, type: types) do
    { func_name, args } = Macros.name_and_args(head)
    { call, cast } = case types do
      list when is_list(list) ->
        { Enum.member?(list, :call), Enum.member?(list, :cast) }
      :call ->
        { true, false }
      :cast ->
        { false, true }
    end

    args_without_state = case List.first(args) do
      { :state, _, _ } -> Enum.drop(args, 1)
      _other_first_val -> args
    end

    called_quote = if call do
      quote do
        def handle_call({ unquote(func_name), unquote_splicing(args_without_state) }, _, var!(state)) do
          unquote(func_name)(unquote_splicing(args)) |> Util.reply(var!(state))
        end
      end
    end

    casted_quote = if cast do
      quote do
        def handle_cast({ unquote(func_name), unquote_splicing(args_without_state) }, var!(state)) do
          unquote(func_name)(unquote_splicing(args)) |> Util.noreply(var!(state))
        end
      end
    end

    quote do
      unquote(called_quote)
      unquote(casted_quote)
    end
  end

  # Allow the "use" syntax
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

end
