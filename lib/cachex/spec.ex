defmodule Cachex.Spec do
  @moduledoc false
  # Model definitions around the Erlang Record syntax.
  import Record

  ###########
  # Records #
  ###########

  # cache entry representation
  @type entry :: record(:entry, key: any, touched: number, ttl: number, value: any)
  defrecord :entry, key: nil, touched: nil, ttl: nil, value: nil

  # fallback state representation
  @type fallback :: record(:fallback, provide: any, default: (any -> any))
  defrecord :fallback, provide: nil, default: nil

  # expiration property representation
  @type expiration :: record(:expiration, default: integer, interval: integer, lazy: boolean)
  defrecord :expiration, default: nil, interval: 3000, lazy: true

  # hook record definition
  @type hook :: record(:hook, args: any, async: boolean, module: atom, options: Keyword.t, provide: [ atom ], ref: pid, timeout: integer, type: :pre | :post)
  defrecord :hook, args: nil, async: true, module: nil, options: [], provide: [], ref: nil, timeout: nil, type: :post

  # hook pairings for cache internals
  @type hooks :: record(:hooks, pre: [ Hook.t ], post: [ Hook.t ])
  defrecord :hooks, pre: [], post: []

  # limit records to define cache bounds
  @type limit :: record(:limit, size: integer, policy: atom, reclaim: number, options: Keyword.t)
  defrecord :limit, size: nil, policy: Cachex.Policy.LRW, reclaim: 0.1, options: []

  #############
  # Constants #
  #############

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

  ##################
  # ETS Generation #
  ##################

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

  # update generation with touch time
  defmacro entry_mod_now(pairs \\ []),
    do: quote(do: entry_mod(unquote([ touched: quote(do: :os.system_time(1000)) ] ++ pairs)))

  # generate entry with default touch time
  defmacro entry_now(pairs),
    do: quote(do: entry(unquote([ touched: quote(do: :os.system_time(1000)) ] ++ pairs)))

  #############
  # Utilities #
  #############

  # positive number testing
  defmacro is_positive_integer(integer),
    do: quote(do: is_integer(unquote(integer)) and unquote(integer) > 0)

  # positive number testing
  defmacro is_negative_integer(integer),
    do: quote(do: is_integer(unquote(integer)) and unquote(integer) < 0)

  # generate names for cache components
  defmacro name(name, suffix) when suffix in [ :eternal, :janitor, :locksmith, :stats ],
    do: quote(do: :"#{unquote(name)}_#{unquote(suffix)}")

  # nillable value validation
  defmacro nillable(value, validator),
    do: quote(do: is_nil(unquote(value)) or apply(unquote(validator), [ unquote(value) ]))
end
