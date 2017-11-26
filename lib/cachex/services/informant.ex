defmodule Cachex.Services.Informant do
  @moduledoc false
  # Parent module for all child hook definitions for a cache.
  #
  # This module will control the supervision tree for all hooks that are
  # associated with a cache. The links inside will create a tree to hold
  # all hooks as children, as well as provide utility functions for new
  # notifications being sent to child hooks for a cache.

  # import our models
  import Cachex.Spec

  # add any aliases
  alias Cachex.Cache
  alias Supervisor.Spec

  @doc """
  Starts a new informant service for a cache's hooks.

  If no hooks exist, this worker is simply ignored and not added to
  the parent supervisor. Otherwise all hooks are added to a supervisor
  to fold out into their own tree.
  """
  def start_link(%Cache{ hooks: hooks(pre: [], post: []) }),
    do: :ignore
  def start_link(%Cache{ hooks: hooks(pre: pre_hooks, post: post_hooks) }) do
    pre_hooks
    |> Enum.concat(post_hooks)
    |> Enum.map(&spec/1)
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  @doc """
  Broadcasts an action to all pre-hooks in a cache.

  This will send a nil result, as the result does not yet exist.
  """
  def broadcast(%Cache{ hooks: hooks(pre: pre_hooks) }, action),
    do: notify(pre_hooks, action, nil)

  @doc """
  Broadcasts an action and result to all post-hooks in a cache.
  """
  def broadcast(%Cache{ hooks: hooks(post: post_hooks) }, action, result),
    do: notify(post_hooks, action, result)

  @doc """
  Links all hooks in a cache to their running process.

  This is a required post-step as hooks are started independently and
  are not named in a deterministic way.
  """
  def link(%Cache{ hooks: hooks(pre: [], post: []) } = cache),
    do: { :ok, cache }
  def link(%Cache{ name: name, hooks: hooks(pre: pre_hooks, post: post_hooks) } = cache) do
    children =
      name
      |> Supervisor.which_children
      |> find_pid(__MODULE__)
      |> Supervisor.which_children

    link_pre  = attach_hook_pid(pre_hooks,  children)
    link_post = attach_hook_pid(post_hooks, children)

    { :ok, %Cache{ cache | hooks: hooks(pre: link_pre, post: link_post) } }
  end

  @doc """
  Notifies a listener of the passed in data.

  If the data is a list, we convert it to a tuple in order to make it easier to
  pattern match against. We accept a list of listeners in order to allow for
  multiple (plugin style) listeners. Initially had the empty clause at the top
  but this way is better (at the very worst it's the same performance).
  """
  def notify([ hook | remaining ], action, result) do
    do_notify(hook, action, result)
    notify(remaining, action, result)
  end
  def notify([], _action, _result),
    do: true

  # Iterates a child spec of a Supervisor and maps the process module names to a
  # list of Hook structs. Wherever there is a match, the PID of the child is added
  # to the Hook so that a Hook struct can track where it lives.
  defp attach_hook_pid(hooks, children) do
    Enum.map(hooks, fn(hook(module: module) = hook) ->
      hook(hook, ref: find_pid(children, module))
   end)
  end

  # Internal emission, used to define whether we send using an async request or
  # not. We also determine whether we should supply a timeout value or not.
  defp do_notify(hook(ref: nil), _action, _result),
    do: nil
  defp do_notify(hook(async: true, ref: ref), action, result),
    do: GenServer.cast(ref, { :cachex_notify, { action, result } })
  defp do_notify(hook(timeout: nil, ref: ref), action, result),
    do: GenServer.call(ref, { :cachex_notify, { action, result } }, :infinity)
  defp do_notify(hook(timeout: val, ref: ref), action, result),
    do: GenServer.call(ref, { :cachex_notify, { action, result }, val }, :infinity)

  # Locates a process identifier for the given module in the child specification
  # provided. If no child is found, the value returned is nil.
  defp find_pid(children, module) do
    Enum.find_value(children, fn
      ({ ^module, pid, _, _ }) -> pid
      (_) -> nil
    end)
  end

  # Generates a Supervisor specification for a hook.
  defp spec(hook(module: module, args: args, options: options)),
    do: Spec.worker(GenServer, [ module, args, options ], [ id: module ])
end
