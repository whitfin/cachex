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
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Put
  alias Cachex.ExecutionError

  ##############
  # Public API #
  ##############

  @doc """
  Starts a new Courier process for a cache.
  """
  @spec start_link(Cachex.Spec.cache()) :: GenServer.on_start()
  def start_link(cache(name: name) = cache),
    do: GenServer.start_link(__MODULE__, cache, name: name(name, :courier))

  @doc """
  Dispatches the Courier to execute a task.

  The task provided must be a closure with arity 0, in order to
  simplify the interfaces internally. This is a blocking remote
  call which will wait until a result can be loaded.
  """
  @spec dispatch(Cachex.Spec.cache(), any, (-> any)) :: any
  def dispatch(cache() = cache, key, task) when is_function(task, 0),
    do: service_call(cache, :courier, {:dispatch, key, task, local_stack()})

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initializes a Courier service using a cache record.
  #
  # This will create a Tuple to store the cache record as well
  # as the Map used to track the internal task referencing.
  def init(cache),
    do: Process.flag(:trap_exit, true) || {:ok, {cache, %{}}}

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
  def handle_call({:dispatch, key, task, stack}, caller, {cache, tasks}) do
    references =
      case Map.get(tasks, key) do
        {pid, listeners} ->
          {pid, [caller | listeners]}

        nil ->
          parent = self()

          worker =
            spawn_link(fn ->
              result =
                try do
                  task.()
                rescue
                  e ->
                    {
                      :error,
                      %ExecutionError{
                        message: Exception.message(e),
                        stack: stack_compat() ++ stack
                      }
                    }
                end

              formatted = Actions.format_fetch_value(result)
              normalized = Actions.normalize_commit(formatted)

              with {:commit, val, options} <- normalized do
                Put.execute(cache, key, val, [const(:notify_false) | options])
              end

              send(parent, {:notify, key, formatted})
            end)

          {worker, [caller]}
      end

    {:noreply, {cache, Map.put(tasks, key, references)}}
  end

  @doc false
  # Receives a notification of a previously completed task.
  #
  # This will update all processes waiting for the result of the
  # specified task, and remove the task from the tracked state.
  #
  # Any processes waiting for the result will be given an `:ok`
  # tag rather than a `:commit` tag, to make it possible to know
  # which call to `fetch/4` actually loaded the backing value.
  def handle_info({:notify, key, result}, {cache, tasks}) do
    callers =
      tasks
      |> Map.get(key, {nil, []})
      |> elem(1)
      |> Enum.reverse()

    with [owner | children] <- callers do
      GenServer.reply(owner, result)

      result =
        case result do
          {:commit, value, _} ->
            {:ok, value}

          {:commit, value} ->
            {:ok, value}

          value ->
            value
        end

      for caller <- children do
        GenServer.reply(caller, result)
      end
    end

    {:noreply, {cache, Map.delete(tasks, key)}}
  end

  @doc false
  # Traps exits from spawned worker processes to sync fail cases.
  #
  # This is necessary to avoid calls to the Courier hanging if a
  # worker process fails unexpectedly. An error will be generated
  # and passed through to the default notify hook to ensure cleanup.
  def handle_info({:EXIT, pid, reason}, {_cache, tasks} = state) do
    case Enum.find(tasks, &match?({_, {^pid, _}}, &1)) do
      {key, _} ->
        handle_info({:notify, key, {:error, reason}}, state)

      nil ->
        {:noreply, state}
    end
  end

  ###############
  # Private API #
  ###############

  # Generates a stack trace prior to dispatch.
  defp local_stack do
    self()
    |> Process.info(:current_stacktrace)
    |> elem(1)
    |> tl
    |> tl
  end
end
