defmodule Cachex.Macros.Stats do
  @moduledoc false
  # Defines a couple of macros needed in the Stats hook. Currently the only macro
  # needed is the shorthand for swallowing a stat change. This simply matches
  # against the provided arguments and then returns the state as-is.

  # alias the main module
  alias Cachex.Macros

  @doc """
  Defines a function body which just returns the passed in state. This is used
  when a certain stats message shouldn't have an effect on the stats container.
  """
  defmacro defswallow(head) do
    { _func_name, args } =
      head
      |> Macros.name_and_args

    quote do
      def handle_notify(unquote_splicing(args), var!(stats)) do
        { :ok, var!(stats) }
      end
    end
  end

  # Allow use of this module
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

end
