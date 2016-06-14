defmodule Cachex.Application do
  use Application

  def start(_type, _args) do
    Cachex.State.init()
  end

end
