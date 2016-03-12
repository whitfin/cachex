defmodule Cachex.Macros.Actions do
  @moduledoc false
  # Provides Macro definitions for use by the Actions module. This defines small
  # wrappers around hook notifications but that's about it at this point. If a
  # body is provided, we pass the body through to do_action, otherwise we just
  # apply the arguments to the provided function (as a delegate).

  # add some aliases
  alias Cachex.Macros

  @doc """
  Forwards the current implementation straight to the do_action internal function.
  This basically acts as a delegate but removes the need to constantly delegate
  internally.
  """
  defmacro defaction(head) do
    { func_name, args } = Macros.name_and_args(head)
    { _, new_args } = Enum.split(args, 1)

    quote do
      def unquote(head) do
        do_action(var!(state), [unquote(func_name)|unquote(new_args)], fn ->
          var!(state).actions.unquote(func_name)(unquote_splicing(args))
        end)
      end
    end
  end

  @doc """
  Simply takes the body of a function and feeds it through the action handler. We
  use this to avoid having to manually feed the function body through the hooks
  system.
  """
  defmacro defaction(head, do: body) do
    { func_name, args } = Macros.name_and_args(head)
    { _, new_args } = Enum.split(args, 1)

    quote do
      def unquote(head) do
        do_action(var!(state), [unquote(func_name)|unquote(new_args)], fn ->
          unquote(body)
        end)
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
