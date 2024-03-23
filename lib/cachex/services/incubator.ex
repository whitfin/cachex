defmodule Cachex.Services.Incubator do
  @moduledoc """
  Parent module for all warmer definitions for a cache.

  The Incubator will control the supervision tree for all warmers that
  are associated with a cache. This is very minimal supervision, with
  no linking back except via the `Supervisor` access functions.
  """
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Starts a new incubation service for a cache.

  This will start a Supervisor to hold all warmer processes as defined in
  the provided cache record. If no warmers are attached in the cache record,
  this will skip creation to avoid unnecessary processes running.
  """
  @spec start_link(Cachex.Spec.cache()) :: Supervisor.on_start()
  def start_link(cache(warmers: [])),
    do: :ignore

  def start_link(cache(warmers: warmers) = cache) do
    warmers
    |> Enum.map(&spec(&1, cache))
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  ###############
  # Private API #
  ###############

  # Generates a Supervisor specification for a hook.
  defp spec(warmer(module: module) = warmer, cache),
    do: %{
      id: module,
      start: {GenServer, :start_link, [module, {cache, warmer}, [name: module]]}
    }
end
