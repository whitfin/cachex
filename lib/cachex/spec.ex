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

  # generate names for cache components
  defmacro name(name, suffix) when suffix in [ :eternal, :janitor, :locksmith, :stats ],
    do: quote(do: :"#{unquote(name)}_#{unquote(suffix)}")

  ##############
  # Validation #
  ##############

  def valid?(entry(touched: touched, ttl: ttl)),
    do: is_integer(touched) and (is_nil(ttl) or is_integer(ttl))

  def valid?(fallback(default: default)),
    do: is_function(default)

  def valid?(hooks(pre: pre, post: post)),
    do: is_list(pre) and is_list(post)

  def valid?(limit(size: size, policy: policy, reclaim: reclaim, options: options)) do
    with true <- (is_nil(size) or (is_number(size) and size > 0)),
         true <- is_atom(policy),
         true <- (is_number(reclaim) and reclaim > 0 and reclaim <= 1),
     do: Keyword.keyword?(options)
  end
end
