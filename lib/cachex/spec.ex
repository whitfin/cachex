defmodule Cachex.Spec do
  @moduledoc false
  # Model definitions around the Erlang Record syntax.
  import Record

  # cache entry representation
  @type entry :: record(:entry, key: any, touched: number, ttl: number, value: any)
  defrecord :entry, key: nil, touched: nil, ttl: nil, value: nil

  # fallback state representation
  @type fallback :: record(:fallback, provide: any, default: (any -> any))
  defrecord :fallback, provide: nil, default: nil

  # hook pairings for cache internals
  @type hooks :: record(:hooks, pre: [ Hook.t ], post: [ Hook.t ])
  defrecord :hooks, pre: [], post: []

  # limit records to define cache bounds
  @type limit :: record(:limit, limit: integer, policy: atom, reclaim: number, options: Keyword.t)
  defrecord :limit, limit: nil, policy: Cachex.Policy.LRW, reclaim: 0.1, options: []

  # constants generation
  defmacro const(:notify_false),
    do: quote(do: [ notify: false ])

  defmacro const(:purge_override_call),
    do: quote(do: { :purge, [[]] })

  defmacro const(:purge_override_result),
    do: quote(do: { :ok, 1 })

  defmacro const(:purge_override),
    do: quote(do: [ via: const(:purge_override_call), hook_result: const(:purge_override_result) ])

  defmacro const(:table_options),
    do: quote(do: [ keypos: 2, read_concurrency: true, write_concurrency: true ])

  # index generation based on ETS
  defmacro entry_idx(key),
    do: quote(do: entry(unquote(key)) + 1)

  # update generation based on ETS
  defmacro entry_mod({ key, val }),
    do: quote(do: { entry_idx(unquote(key)), unquote(val) })

  # multi update generation based on ETS
  defmacro entry_mod(updates) when is_list(updates),
    do: for pair <- updates,
      do: quote(do: entry_mod(unquote(pair)))

  # generate entry with default touch time
  defmacro entry_now(pairs),
    do: quote(do: entry(unquote([ touched: quote(do: :os.system_time(1000)) ] ++ pairs)))

  # generate names for cache components
  defmacro name(name, suffix) when suffix in [ :eternal, :janitor, :locksmith, :stats ],
    do: quote(do: :"#{unquote(name)}_#{unquote(suffix)}")
end
