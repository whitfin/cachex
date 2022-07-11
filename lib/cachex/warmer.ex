defmodule Cachex.Warmer do
  @moduledoc """
  Module controlling cache warmer behaviour definitions.

  This module defines the cache warming implementation for Cachex, allowing the
  user to register warmers against a cache to populate the tables on an interval.
  Doing this allows for easy pulling against expensive values (such as those from
  a backing database or remote server), without risking heavy usage.

  Warmers will block when the cache is started to ensure that the application
  will not complete booting up, until your cache has been warmed. This guarantees
  that there will not be any time where the application is available, without the
  desired data in the cache.

  Warmers are fired on a schedule, and are exposed via a very simple behaviour of
  just an interval and a block to execute on the interval. It should be noted that
  this is a moving interval, and it resets after execution has completed.
  """

  #############
  # Behaviour #
  #############

  @doc """
  Returns the interval this warmer will execute on.

  This must be an integer representing a count of milliseconds to wait before
  the next execution of the warmer. Anything else will cause either invalidation
  errors on cache startup, or crashes at runtime.
  """
  @callback interval :: integer

  @doc """
  Executes actions to warm a cache instance on interval.

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

      # enforce the behaviour
      @behaviour Cachex.Warmer

      @doc false
      # Initializes the warmer from a provided state.
      #
      # Initialization will trigger an initial cache warming, and store
      # the provided state for later to provide during further warming.
      def init({cache, warmer(sync: sync, state: state)}) do
        if sync do
          handle_info(:cachex_warmer, {cache, state})
        else
          trigger()
        end

        {:ok, {cache, state}}
      end

      @doc false
      # Warms a number of keys in a cache.
      #
      # This is done by calling the `execute/1` callback with the state
      # stored in the main process state. The results are placed into the
      # cache via `Cachex.put_many/3` if returns in a Tuple tagged with the
      # `:ok` atom. If `:ignore` is returned, nothing happens aside from
      # scheduling the next execution of the warming to occur on interval.
      def handle_info(:cachex_warmer, {cache, state} = persist_state) do
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

        # fire again!
        trigger()

        # repeat with the state
        {:noreply, persist_state}
      end

      # Trigger a run to happen in the future.
      defp trigger,
        do: :erlang.send_after(interval(), self(), :cachex_warmer)
    end
  end
end
