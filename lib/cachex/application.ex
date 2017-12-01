defmodule Cachex.Application do
  @moduledoc """
  Application callback to start any global services.

  This will start all needed services for Cachex using the `Cachex.Services`
  module, rather than hardcoding any logic into this binding module.
  """
  use Application

  @doc """
  Starts the global services tree for Cachex.
  """
  def start(_type, _args) do
    # Define child supervisors to be supervised
    services = Cachex.Services.app_spec()
    options  = [strategy: :one_for_one, name: __MODULE__]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    Supervisor.start_link(services, options)
  end
end
