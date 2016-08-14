one_hour = :timer.hours(1)
tomorrow = Cachex.Util.now() + (1000 * 60 * 60 * 24)

Application.ensure_all_started(:cachex)

Cachex.start(:bench_cache)

Cachex.set(:bench_cache, "decr_test", 0)
Cachex.set(:bench_cache, "expire_at_test", "expire_at_value")
Cachex.set(:bench_cache, "expire_test", "expire_value")
Cachex.set(:bench_cache, "get_test", "get_value")
Cachex.set(:bench_cache, "gad_test", "gad_value")
Cachex.set(:bench_cache, "incr_test", 0)
Cachex.set(:bench_cache, "persist_test", 0)
Cachex.set(:bench_cache, "refresh_test", "refresh_value", ttl: one_hour)
Cachex.set(:bench_cache, "ttl_test", "ttl_value", ttl: one_hour)
Cachex.set(:bench_cache, "update_test", "update_value")

Benchee.run(%{ time: 10, warmup: 10, parallel: 1 }, [
  { "count",      fn -> Cachex.count(:bench_cache) end },
  { "decr",       fn -> Cachex.decr(:bench_cache, "decr_test") end },
  { "del",        fn -> Cachex.del(:bench_cache, "del_test") end },
  { "empty?",     fn -> Cachex.empty?(:bench_cache) end },
  { "exists?",    fn -> Cachex.exists?(:bench_cache, "exists_test") end },
  { "expire",     fn -> Cachex.expire(:bench_cache, "expire_test", one_hour) end },
  { "expire_at",  fn -> Cachex.expire_at(:bench_cache, "expire_at_test", tomorrow) end },
  { "get",        fn -> Cachex.get(:bench_cache, "get_test") end },
  { "gad",        fn -> Cachex.get_and_update(:bench_cache, "gad_test", &(&1)) end },
  { "incr",       fn -> Cachex.incr(:bench_cache, "incr_test") end },
  { "keys",       fn -> Cachex.keys(:bench_cache) end },
  { "persist",    fn -> Cachex.persist(:bench_cache, "persist_test") end },
  { "refresh",    fn -> Cachex.refresh(:bench_cache, "refresh_test") end },
  { "set",        fn -> Cachex.set(:bench_cache, "set_test", "set_value") end },
  { "size",       fn -> Cachex.size(:bench_cache) end },
  { "take",       fn -> Cachex.take(:bench_cache, "take_test") end },
  { "ttl",        fn -> Cachex.ttl(:bench_cache, "ttl_test") end },
  { "update",     fn -> Cachex.update(:bench_cache, "update_test", "update_value") end }
])
