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
  @spec start_link(Spec.cache) :: Supervisor.on_start
  def start_link(cache(hooks: hooks(pre: [], post: []))),
    do: :ignore
  def start_link(cache(hooks: hooks(pre: pre_hooks, post: post_hooks))) do
    pre_hooks
    |> Enum.concat(post_hooks)
    |> Enum.map(&spec/1)
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  @doc """
  Broadcasts an action to all pre-hooks in a cache.

  This will send a nil result, as the result does not yet exist.
  """
  @spec broadcast(Spec.cache, tuple) :: :ok
  def broadcast(cache(hooks: hooks(pre: pre_hooks)), action),
    do: notify(pre_hooks, action, nil)

  @doc """
  Broadcasts an action and result to all post-hooks in a cache.
  """
  @spec broadcast(Spec.cache, tuple, any) :: :ok
  def broadcast(cache(hooks: hooks(post: post_hooks)), action, result),
    do: notify(post_hooks, action, result)

  @doc """
  Links all hooks in a cache to their running process.

  This is a required post-step as hooks are started independently and
  are not named in a deterministic way. It will look up all hooks using
  the Supervisor children and place them in a modified cache record.
  """
  @spec link(Spec.cache) :: { :ok, Spec.cache }
  def link(cache(hooks: hooks(pre: [], post: [])) = cache),
    do: { :ok, cache }
  def link(cache(name: name, hooks: hooks(pre: pre_hooks, post: post_hooks)) = cache) do
    children =
      name
      |> Supervisor.which_children
      |> find_pid(__MODULE__)
      |> Supervisor.which_children

    link_pre  = attach_hook_pid(pre_hooks,  children)
    link_post = attach_hook_pid(post_hooks, children)

    { :ok, cache(cache, hooks: hooks(pre: link_pre, post: link_post)) }
  end

  @doc """
  Notifies a set of hooks of the passed in data.

  This is the underlying implementation for `broadcast/2` and `broadcast/3`,
  but it's general purpose enough that it's exposed as part of the public API.
  """
  @spec notify([ Spec.hook ], tuple, any) :: :ok
  def notify(hooks, action, result) when is_list(hooks) do
    Enum.each(hooks, fn
      # not running, so skip
      (hook(ref: nil)) -> nil

      # handling of asynchronous hooks
      (hook(async: true, ref: ref)) ->
        send(ref, { :cachex_notify, { action, result } })

      # handle hooks without a timeout
      (hook(timeout: nil, ref: ref)) ->
        GenServer.call(ref, { :cachex_notify, { action, result } }, :infinity)

      # handle hooks with a timeout
      (hook(timeout: val, ref: ref)) ->
        GenServer.call(ref, { :cachex_notify, { action, result }, val }, :infinity)
    end)
  end

  ###############
  # Private API #
  ###############

  # Iterates a list of hooks and finds their reference in list of children.
  #
  # When there is a reference found, the hook is updated with the new PID.
  defp attach_hook_pid(hooks, children) do
    Enum.map(hooks, fn(hook(module: module) = hook) ->
      hook(hook, ref: find_pid(children, module))
   end)
  end

  # Locates a process identifier for the given module.
  #
  # This uses a list of child modules; if no child is
  # found, the value returned is nil.
  defp find_pid(children, module) do
    Enum.find_value(children, fn
      ({ ^module, pid, _, _ }) -> pid
      (_) -> nil
    end)
  end

  # Generates a Supervisor specification for a hook.
  defp spec(hook(module: module, args: args, options: options)),
    do: Supervisor.Spec.worker(GenServer, [ module, args, options ], [ id: module ])
end
