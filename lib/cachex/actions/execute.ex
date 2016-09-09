defmodule Cachex.Actions.Execute do

  alias Cachex.State

  def execute(%State{ } = state, operation, options \\ []) when is_list(options) do
    { :ok, operation.(state) }
  end

end
