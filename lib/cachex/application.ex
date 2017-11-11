defmodule Cachex.Application do
  # define application
  use Application

  @moduledoc false
  # Application callback to start any needed resources. We start all
  # needed services using the services module, rather than hardcoding
  # any logic into this application module.

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = Cachex.Services.app_spec()

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
