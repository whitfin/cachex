defmodule Cachex.Services.Locksmith.Queue do
  @moduledoc false
  # Transaction queue backing a cache instance.
  #
  # This has to live outside of the `Cachex.Services.Locksmith` global process
  # as otherwise caches would then compete with each other for resources which
  # is far from optimal.
  #
  # Each cache will therefore have their own queue process, represented in this
  # module, and will operate using the utilities provided in the main Locksmith
  # service module (rather than using this module directly).
  import Cachex.Spec
  import Cachex.Services.Locksmith

  ##############
  # Public API #
  ##############

  @doc """
  Starts the internal server process backing this queue.

  This is little more than starting a GenServer process using this module,
  although it does use the provided cache record to name the new server.
  """
  @spec start_link(Cachex.t()) :: GenServer.on_start()
  def start_link(cache(name: name) = cache),
    do: GenServer.start_link(__MODULE__, cache, name: name(name, :locksmith))

  @doc """
  Executes a function in a lock-free context.
  """
  @spec execute(Cachex.t(), (() -> any)) :: any
  def execute(cache() = cache, func) when is_function(func, 0),
    do: service_call(cache, :locksmith, {:exec, func})

  @doc """
  Executes a function in a transactional context.
  """
  @spec transaction(Cachex.t(), [any], (() -> any)) :: any
  def transaction(cache() = cache, keys, func)
      when is_list(keys) and is_function(func, 0),
      do: service_call(cache, :locksmith, {:transaction, keys, func})

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initializes the new server process instance.
  #
  # This will signal the process as transactional, which
  # is used by the main Locksmith service for optimizations.
  def init(cache) do
    # signal transactional
    start_transaction()
    # cache is state
    {:ok, cache}
  end

  @doc false
  # Executes a function in a lock-free context.
  #
  # Because locks are handled sequentially inside this process, this execution
  # can guarantee that there are no locks set on the table when it fires.
  def handle_call({:exec, func}, _ctx, cache),
    do: {:reply, safe_exec(func), cache}

  @doc false
  # Executes a function in a transactional context.
  #
  # This will lock any required keys before executing any writes, and remove the
  # locks after execution. The key here is that the locks set on a key will stop
  # other processes from writing them, and force them to queue their writes
  # inside this queue process instead.
  def handle_call({:transaction, keys, func}, _ctx, cache) do
    true = lock(cache, keys)
    val = safe_exec(func)
    true = unlock(cache, keys)

    {:reply, val, cache}
  end

  ###############
  # Private API #
  ###############

  # Wraps a function in a rescue clause to provide safety.
  #
  # Any errors which occur are rescued and returned in an
  # `:error` tagged Tuple to avoid crashing the process.
  defp safe_exec(fun) do
    fun.()
  rescue
    e -> {:error, Exception.message(e)}
  end
end
