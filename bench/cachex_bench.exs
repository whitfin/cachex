one_hour = :timer.hours(1)
tomorrow = Cachex.Util.now() + (1000 * 60 * 60 * 24)

{ parsed, _argv, _errors } = OptionParser.parse(System.argv(), [
  aliases: [ s: :state ],
  strict:  [ state: :boolean ]
])

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

cache = if parsed[:with_state] do
  Cachex.inspect!(:bench_cache, :state)
else
  :bench_cache
end

Benchee.run(%{ time: 5, warmup: 5, parallel: 1, print: %{ fast_warning: false, comparison: false } }, [
  { "count",      fn -> Cachex.count(cache) end },
  { "decr",       fn -> Cachex.decr(cache, "decr_test") end },
  { "del",        fn -> Cachex.del(cache, "del_test") end },
  { "empty?",     fn -> Cachex.empty?(cache) end },
  { "exists?",    fn -> Cachex.exists?(cache, "exists_test") end },
  { "expire",     fn -> Cachex.expire(cache, "expire_test", one_hour) end },
  { "expire_at",  fn -> Cachex.expire_at(cache, "expire_at_test", tomorrow) end },
  { "get",        fn -> Cachex.get(cache, "get_test") end },
  { "gad",        fn -> Cachex.get_and_update(cache, "gad_test", &(&1)) end },
  { "incr",       fn -> Cachex.incr(cache, "incr_test") end },
  { "keys",       fn -> Cachex.keys(cache) end },
  { "persist",    fn -> Cachex.persist(cache, "persist_test") end },
  { "refresh",    fn -> Cachex.refresh(cache, "refresh_test") end },
  { "set",        fn -> Cachex.set(cache, "set_test", "set_value") end },
  { "size",       fn -> Cachex.size(cache) end },
  { "take",       fn -> Cachex.take(cache, "take_test") end },
  { "ttl",        fn -> Cachex.ttl(cache, "ttl_test") end },
  { "update",     fn -> Cachex.update(cache, "update_test", "update_value") end }
])
