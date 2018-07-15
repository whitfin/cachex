defmodule Cachex.Services.Courier do
  @moduledoc """
  Dispatch service to retrieve values from remote calls.

  The Courier provides the main implementation for fallbacks triggered
  by calls to the `fetch()` command. It acts as a synchronized execution
  for tasks to avoid duplicating calls when loading.

  The Courier uses a very simple algorithm to determine when to execute
  a fallback, so there's very little overhead to synchronizing calls
  through it. As tasks are dispatched via spawned processes, there's
  very little action actually happening in the service process itself.
  """
  use GenServer

  # import spec macros
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions.Put

  ##############
  # Public API #
  ##############

  @doc """
  Starts a new Courier process for a cache.
  """
  @spec start_link(Spec.cache) :: GenServer.on_start
  def start_link(cache(name: name) = cache),
    do: GenServer.start_link(__MODULE__, cache, [ name: name(name, :courier) ])

  @doc """
  Dispatches the Courier to execute a task.

  The task provided must be a closure with arity 0, in order to
  simplify the interfaces internally. This is a blocking remote
  call which will wait until a result can be loaded.
  """
  @spec dispatch(Spec.cache, any, (() -> any)) :: any
  def dispatch(cache() = cache, key, task) when is_function(task, 0),
    do: service_call(cache, :courier, { :dispatch, key, task })

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initializes a Courier service using a cache record.
  #
  # This will create a Tuple to store the cache record as well
  # as the Map used to track the internal task referencing.
  def init(cache),
    do: { :ok, { cache, %{ } } }

  @doc false
  # Dispatches a tasks to be carried out by the Courier.
  #
  # Tasks will only be executed if they're not already in progress. This
  # is only tracked on a key level, so it's not possible to track different
  # tasks for a given key.
  #
  # Due to the nature of the async behaviour, this call will return before
  # the task has been completed, and the :notify callback will receive the
  # results from the task after completion (regardless of outcome).
  def handle_call({ :dispatch, key, task }, caller, { cache, tasks }) do
    references =
      case Map.get(tasks, key, []) do
        [] ->
          parent = self()
          spawn(fn ->
            result =
              try do
                task.()
              rescue
                e -> { :error, Exception.message(e) }
              end
            normalized = normalize_commit(result)

            with { :commit, val } <- normalized do
              Put.execute(cache, key, val, const(:notify_false))
            end

            send(parent, { :notify, key, normalized })
          end)
          [ caller ]
        li ->
          [ caller | li ]
      end

    { :noreply, { cache, Map.put(tasks, key, references) } }
  end

  @doc false
  # Receives a notification of a previously completed task.
  #
  # This will update all processes waiting for the result of the
  # specified task, and remove the task from the tracked state.
  def handle_info({ :notify, key, result }, { cache, tasks }) do
    for caller <- Map.get(tasks, key, []) do
      GenServer.reply(caller, result)
    end

    { :noreply, { cache, Map.delete(tasks, key) } }
  end
end
