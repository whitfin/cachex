import Cachex.Spec

one_hour = :timer.hours(1)
tomorrow = now() + (1000 * 60 * 60 * 24)

Application.ensure_all_started(:cachex)

Cachex.start(:bench_cache)

Cachex.put(:bench_cache, "decr_test", 0)
Cachex.put(:bench_cache, "expire_at_test", "expire_at_value")
Cachex.put(:bench_cache, "expire_test", "expire_value")
Cachex.put(:bench_cache, "fetch_test", "fetch_value")
Cachex.put(:bench_cache, "get_test", "get_value")
Cachex.put(:bench_cache, "gad_test", "gad_value")
Cachex.put(:bench_cache, "incr_test", 0)
Cachex.put(:bench_cache, "persist_test", 0)
Cachex.put(:bench_cache, "refresh_test", "refresh_value", ttl: one_hour)
Cachex.put(:bench_cache, "ttl_test", "ttl_value", ttl: one_hour)
Cachex.put(:bench_cache, "update_test", "update_value")

use_state = System.get_env("CACHEX_BENCH_STATE") == "true"
use_trans = System.get_env("CACHEX_BENCH_TRANSACTIONS") == "true"

if use_trans do
  Cachex.Services.Overseer.update(:bench_cache, fn(state) ->
    cache(state, transactional: true)
  end)
end

cache = if use_state do
  Cachex.inspect!(:bench_cache, :cache)
else
  :bench_cache
end

benchmarks = %{
  "count" => fn ->
    Cachex.count(cache)
  end,
  "decr" => fn ->
    Cachex.decr(cache, "decr_test")
  end,
  "del" => fn ->
    Cachex.del(cache, "del_test")
  end,
  "empty?" => fn ->
    Cachex.empty?(cache)
  end,
  "exists?" => fn ->
    Cachex.exists?(cache, "exists_test")
  end,
  "expire" => fn ->
    Cachex.expire(cache, "expire_test", one_hour)
  end,
  "expire_at" => fn ->
    Cachex.expire_at(cache, "expire_at_test", tomorrow)
  end,
  "fetch" => fn ->
    Cachex.fetch(cache, "fetch_test", &(&1))
  end,
  "get" => fn ->
    Cachex.get(cache, "get_test")
  end,
  "get_and_update" => fn ->
    Cachex.get_and_update(cache, "gad_test", &(&1))
  end,
  "incr" => fn ->
    Cachex.incr(cache, "incr_test")
  end,
  "keys" => fn ->
    Cachex.keys(cache)
  end,
  "persist" => fn ->
    Cachex.persist(cache, "persist_test")
  end,
  "put" => fn ->
    Cachex.put(cache, "put_test", "put_value")
  end,
  "refresh" => fn ->
    Cachex.refresh(cache, "refresh_test")
  end,
  "size" => fn ->
    Cachex.size(cache)
  end,
  "stream" => fn ->
    Cachex.stream(cache)
  end,
  "take" => fn ->
    Cachex.take(cache, "take_test")
  end,
  "ttl" => fn ->
    Cachex.ttl(cache, "ttl_test")
  end,
  "update" => fn ->
    Cachex.update(cache, "update_test", "update_value")
  end
}

Benchee.run(benchmarks, [
  console: [
    comparison: false,
    extended_statistics: true
  ],
  formatters: [
    Benchee.Formatters.Console,
    Benchee.Formatters.HTML
  ],
  formatter_options: [
    html: [
      auto_open: false
    ]
  ],
  print: [
    fast_warning: false
  ]
])
