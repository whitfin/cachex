defmodule Cachex.Services.Informant do
  @moduledoc """
  Parent module for all child hook definitions for a cache.

  This module will control the supervision tree for all hooks that are
  associated with a cache. The links inside will create a tree to hold
  all hooks as children, as well as provide utility functions for new
  notifications being sent to child hooks for a cache.
  """
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Starts a new Informant service for a cache.

  This will start a Supervisor to hold all hook processes as defined in
  the provided cache record. If no hooks are attached in the cache record,
  this will skip creating an unnecessary Supervisor process.
  """
  @spec start_link(Cachex.t()) :: Supervisor.on_start()
  def start_link(cache(hooks: hooks(pre: [], post: []))),
    do: :ignore

  def start_link(cache(hooks: hooks(pre: pre, post: post))) do
    pre
    |> Enum.concat(post)
    |> Enum.map(&spec/1)
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  @doc """
  Broadcasts an action to all pre-hooks in a cache.

  This will send a nil result, as the result does not yet exist.
  """
  @spec broadcast(Cachex.t(), tuple) :: :ok
  def broadcast(cache(hooks: hooks(pre: pre)), action),
    do: broadcast_action(pre, action, nil)

  @doc """
  Broadcasts an action and result to all post-hooks in a cache.
  """
  @spec broadcast(Cachex.t(), tuple, any) :: :ok
  def broadcast(cache(hooks: hooks(post: post)), action, result),
    do: broadcast_action(post, action, result)

  @doc """
  Notifies a set of hooks of the passed in data.

  This is the underlying implementation for `broadcast/2` and `broadcast/3`,
  but it's general purpose enough that it's exposed as part of the public API.
  """
  @spec notify([Cachex.Spec.hook()], tuple, any) :: :ok
  def notify(hooks, {_name, _args} = action, result) when is_list(hooks) do
    Enum.each(hooks, fn
      # not running, so skip
      hook(name: nil) ->
        nil

      # handling of running hooks
      hook(name: name, module: module) ->
        # define the base payload, regardless of type
        payload = {:cachex_notify, {action, result}}

        # handle async vs. sync
        case module.async?() do
          true -> send(name, payload)
          false -> GenServer.call(name, payload, :infinity)
        end
    end)
  end

  ###############
  # Private API #
  ###############

  # Broadcasts an action to hooks listening for it.
  #
  # This will enforce the actions list inside a hook definition to ensure
  # that hooks only receive actions that they currently care about.
  defp broadcast_action(hooks, {action, _args} = msg, result) do
    actionable =
      Enum.filter(hooks, fn hook(module: module) ->
        case module.actions() do
          :all -> true
          enum -> action in enum
        end
      end)

    notify(actionable, msg, result)
  end

  # Generates a Supervisor specification for a hook.
  defp spec(hook(module: module, name: name, state: state)) do
    options =
      case name do
        nil -> [module, state]
        val -> [module, state, [name: val]]
      end

    %{id: module, start: {GenServer, :start_link, options}}
  end
end
