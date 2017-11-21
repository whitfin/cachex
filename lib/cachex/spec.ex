defmodule Cachex.Spec do
  @moduledoc false
  # Model definitions around the Erlang Record syntax.
  import Record

  # cache entry representation
  @type entry :: record(:entry, key: any, touched: number, ttl: number, value: any)
  defrecord :entry, key: nil, touched: nil, ttl: nil, value: nil

  # hook pairings for cache internals
  @type hooks :: record(:hooks, pre: [ Hook.t ], post: [ Hook.t ])
  defrecord :hooks, pre: [], post: []

  # index generation based on ETS
  defmacro entry_idx(key),
    do: quote(do: entry(unquote(key)) + 1)

  # update generation based on ETS
  defmacro entry_mod(key, val) do
    quote(do: { entry_idx(unquote(key)), unquote(val) })
  end

  # multi update generation based on ETS
  defmacro entry_mod(updates) do
    for { key, val } <- updates do
      quote(do: entry_mod(unquote(key), unquote(val)))
    end
  end

  # generate entry with default touch time
  defmacro entry_now(pairs \\ []),
    do: quote(do: entry(unquote([ touched: quote(do: :os.system_time(1000)) ] ++ pairs)))
end
