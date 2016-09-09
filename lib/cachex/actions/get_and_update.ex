defmodule Cachex.Actions.GetAndUpdate do

  alias Cachex.Actions
  alias Cachex.Actions.Get
  alias Cachex.Actions.Set
  alias Cachex.Actions.Update

  alias Cachex.LockManager
  alias Cachex.State

  def execute(%State{ } = state, key, update_fun, options \\ []) when is_function(update_fun) and is_list(options) do
    Actions.do_action(state, { :get_and_update, [ key, update_fun, options ] }, fn ->

      LockManager.transaction(state, [ key ], fn ->
        { status, value } = Get.execute(state, key, [ notify: false ] ++ options)

        tempv = update_fun.(value)

        status
        |> write_mod
        |> apply(:execute, [ state, key, tempv, [ notify: false ] ])

        { status, tempv }
      end)

    end)

  end

  defp write_mod(:missing), do: Set
  defp write_mod(_others_), do: Update

end
