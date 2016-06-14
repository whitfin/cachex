defmodule Cachex.Application do
  use Application

  @moduledoc false
  # Application callback to start any needed resources

  def start(_type, _args) do
    Cachex.State.start_link()
  end
end
