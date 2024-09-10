defmodule Cachex.Warmer do
  @moduledoc """
  Module controlling cache warmer behaviour definitions.

  This module defines the cache warming implementation for Cachex, allowing the
  user to register warmers against a cache to populate the tables periodically.
  Doing this allows for easy pulling against expensive values (such as those from
  a backing database or remote server), without risking heavy usage.

  Warmers will block when the cache is started to ensure that the application
  will not complete booting up, until your cache has been warmed. This guarantees
  that there will not be any time where the application is available, without the
  desired data in the cache.

  Warmers are fired on a schedule, and are exposed via a very simple behaviour of
  just a block to execute periodically.
  """

  #############
  # Behaviour #
  #############

  @doc """
  Executes actions to warm a cache instance.

  This can either return values to set in the cache, or the atom `:ignore` to
  signal that there's nothing to be set at this point in time. Values to be set
  should be returned as `{ :ok, pairs }` where pairs is a list of `{ key, value }`
  pairs to place into the cache via `Cachex.put_many/3`.

  If you wish to provide expiration against the keys, you can return a Tuple in
  the form `{ :ok, pairs, opts }` where `opts` is a list of options as accepted
  by the `Cachex.put_many/3` function, thus allowing you to expire your warmed
  data. Unless this is provided, there is no explicit expiration associated with
  warmed values (as predicting the appropriate expiration is not possible).

  The argument provided here is the one provided as state to the warmer records
  at cache configuration time; it will be `nil` if none was provided.
  """
  @callback execute(state :: any) ::
              :ignore
              | {:ok, pairs :: [{key :: any, value :: any}]}
              | {:ok, pairs :: [{key :: any, value :: any}],
                 options :: Keyword.t()}

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      use GenServer
      use Cachex.Provision

      import Cachex.Spec

      # enforce the behaviour
      @behaviour Cachex.Warmer

      @doc """
      Return the provisions warmers require.
      """
      def provisions,
        do: [:cache]

      @doc false
      # Initializes the warmer from a provided state.
      #
      # Initialization will trigger an initial cache warming, and store
      # the provided state for later to provide during further warming.
      def init({cache() = cache, warmer(interval: interval, state: state)}) do
        {:ok, {cache, state, interval, nil}}
      end

      @doc false
      # Warms a number of keys in a cache.
      #
      # This is a blocking binding to `handle_info(:cache_warmer)`. See
      # the documentation of that implementation for more information.
      def handle_call(:cachex_warmer, _from, state) do
        {:noreply, new_state} = handle_info(:cachex_warmer, state)
        {:reply, :ok, new_state}
      end

      @doc false
      # Warms a number of keys in a cache.
      #
      # This is done by calling the `execute/1` callback with the state
      # stored in the main process state. The results are placed into the
      # cache via `Cachex.put_many/3` if returns in a Tuple tagged with the
      # `:ok` atom. If `:ignore` is returned, nothing happens aside from
      # scheduling the next execution of the warming to occur on interval.
      def handle_info(:cachex_warmer, {cache, state, interval, timer}) do
        # clean our any existing timers
        if timer, do: Process.cancel_timer(timer)

        # execute, passing state
        case execute(state) do
          # no changes
          :ignore ->
            :ignore

          # set pairs without options
          {:ok, pairs} ->
            Cachex.put_many(cache, pairs)

          # set pairs with options
          {:ok, pairs, options} ->
            Cachex.put_many(cache, pairs, options)
        end

        # trigger the warming to happen again after the interval
        new_timer =
          case interval do
            nil -> nil
            val -> :erlang.send_after(val, self(), :cachex_warmer)
          end

        # pass the new state
        {:noreply, {cache, state, interval, new_timer}}
      end

      @doc false
      # Receives a provisioned cache instance.
      #
      # The provided cache is then stored in the state and used for cache calls going
      # forwards, in order to skip the lookups inside the cache overseer for performance.
      def handle_provision({:cache, cache}, {_cache, state, interval, timer}),
        do: {:ok, {cache, state, interval, timer}}
    end
  end
end
