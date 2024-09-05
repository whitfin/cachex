import Cachex.Spec

one_hour = :timer.hours(1)
tomorrow = now() + 1000 * 60 * 60 * 24

Application.ensure_all_started(:cachex)

with_env = fn var, caches ->
  if System.get_env(var) in ["true", "1"] do
    caches
  else
    []
  end
end

caches =
  List.flatten([
    [
      {:name, []},
      {:state, [inspect: true]}
    ],
    with_env.("CACHEX_BENCH_COMPRESS", [
      {:name_compressed, [compressed: true]},
      {:state_compressed, [inspect: true, compressed: true]}
    ]),
    with_env.("CACHEX_BENCH_TRANSACTIONS", [
      {:name_transactional, [transactionl: true]},
      {:state_transactional, [inspect: true, transactionl: true]}
    ])
  ])

inputs =
  for {name, options} <- caches do
    Cachex.start(name, options)

    Cachex.put(name, "decr_test", 0)
    Cachex.put(name, "expire_at_test", "expire_at_value")
    Cachex.put(name, "expire_test", "expire_value")
    Cachex.put(name, "fetch_test", "fetch_value")
    Cachex.put(name, "get_test", "get_value")
    Cachex.put(name, "gad_test", "gad_value")
    Cachex.put(name, "incr_test", 0)
    Cachex.put(name, "persist_test", 0)
    Cachex.put(name, "refresh_test", "refresh_value", expiration: one_hour)
    Cachex.put(name, "touch_test", "touch_value", expiration: one_hour)
    Cachex.put(name, "ttl_test", "ttl_value", expiration: one_hour)
    Cachex.put(name, "update_test", "update_value")

    if Keyword.get(options, :inspect) do
      {"#{name}", Cachex.inspect!(name, :cache)}
    else
      {"#{name}", name}
    end
  end

Benchee.run(
  %{
    "count" => fn cache ->
      Cachex.count(cache)
    end,
    "decr" => fn cache ->
      Cachex.decr(cache, "decr_test")
    end,
    "del" => fn cache ->
      Cachex.del(cache, "del_test")
    end,
    "empty?" => fn cache ->
      Cachex.empty?(cache)
    end,
    "exists?" => fn cache ->
      Cachex.exists?(cache, "exists_test")
    end,
    "expire" => fn cache ->
      Cachex.expire(cache, "expire_test", one_hour)
    end,
    "expire_at" => fn cache ->
      Cachex.expire_at(cache, "expire_at_test", tomorrow)
    end,
    "fetch" => fn cache ->
      Cachex.fetch(cache, "fetch_test", & &1)
    end,
    "get" => fn cache ->
      Cachex.get(cache, "get_test")
    end,
    "get_and_update" => fn cache ->
      Cachex.get_and_update(cache, "gad_test", & &1)
    end,
    "incr" => fn cache ->
      Cachex.incr(cache, "incr_test")
    end,
    "keys" => fn cache ->
      Cachex.keys(cache)
    end,
    "persist" => fn cache ->
      Cachex.persist(cache, "persist_test")
    end,
    "purge" => fn cache ->
      Cachex.purge(cache)
    end,
    "put" => fn cache ->
      Cachex.put(cache, "put_test", "put_value")
    end,
    "put_many" => fn cache ->
      Cachex.put_many(cache, [{"put_test", "put_value"}])
    end,
    "refresh" => fn cache ->
      Cachex.refresh(cache, "refresh_test")
    end,
    "size" => fn cache ->
      Cachex.size(cache)
    end,
    "stats" => fn cache ->
      Cachex.stats(cache)
    end,
    "stream" => fn cache ->
      Cachex.stream(cache)
    end,
    "take" => fn cache ->
      Cachex.take(cache, "take_test")
    end,
    "touch" => fn cache ->
      Cachex.touch(cache, "touch_test")
    end,
    "ttl" => fn cache ->
      Cachex.ttl(cache, "ttl_test")
    end,
    "update" => fn cache ->
      Cachex.update(cache, "update_test", "update_value")
    end
  },
  formatters: [
    {
      Benchee.Formatters.Console,
      [
        comparison: false,
        extended_statistics: false
      ]
    }
  ],
  inputs: Map.new(inputs),
  print: [
    fast_warning: false
  ]
)
