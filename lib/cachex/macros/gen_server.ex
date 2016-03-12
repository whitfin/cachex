defmodule Cachex.Macros.GenServer do
  @moduledoc false
  # Provides a number of Macros to make it more convenient to create any of the
  # GenServer functions (handle_call/handle_cast/handle_info). This is purely for
  # shorthand convenience and doesn't really provide anything too special.

  # alias the parent module
  alias Cachex.Macros

  @doc """
  Small macro for detailing handle_call functions, without having to pay attention
  to the syntax. You can simply define them as `defcall my_func(arg1) do:` as an
  example. There is no support for guards, but no logic happens inside the worker
  with regards to arguments anyway.
  """
  defmacro defcall(head, do: body) do
    { func_name, args } = Macros.name_and_args(head)

    quote do
      def handle_call({ unquote(func_name), unquote_splicing(args) }, _, var!(state)) do
        unquote(body)
      end
    end
  end

  @doc """
  Small macro for detailing handle_cast functions, without having to pay attention
  to the syntax. You can simply define them as `defcast my_func(arg1) do:` as an
  example. There is no support for guards, but no logic happens inside the worker
  with regards to arguments anyway.
  """
  defmacro defcast(head, do: body) do
    { func_name, args } = Macros.name_and_args(head)

    quote do
      def handle_cast({ unquote(func_name), unquote_splicing(args) }, var!(state)) do
        unquote(body)
      end
    end
  end

  @doc """
  Very small wrapper around handle_info calls so you can define your own message
  handler with little effort. Again nothing special, but saves on boilerplate.
  """
  defmacro definfo(head, do: body) do
    { func_name, _ } = Macros.name_and_args(head)

    quote do
      def handle_info(unquote(func_name), var!(state)) do
        unquote(body)
      end
    end
  end

  # Allow the "use" syntax
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

end
