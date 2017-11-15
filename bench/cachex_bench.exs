defmodule CachexBench do
  use Benchfella

  @one_hour :timer.hours(1)
  @tomorrow Cachex.Util.now() + (1000 * 60 * 60 * 24)

  setup_all do
    Application.ensure_all_started(:cachex)

    Cachex.start(:bench_cache)

    Cachex.set(:bench_cache, "decr_test", 0)
    Cachex.set(:bench_cache, "expire_at_test", "expire_at_value")
    Cachex.set(:bench_cache, "expire_test", "expire_value")
    Cachex.set(:bench_cache, "get_test", "get_value")
    Cachex.set(:bench_cache, "gad_test", "gad_value")
    Cachex.set(:bench_cache, "incr_test", 0)
    Cachex.set(:bench_cache, "persist_test", 0)
    Cachex.set(:bench_cache, "refresh_test", "refresh_value", ttl: @one_hour)
    Cachex.set(:bench_cache, "ttl_test", "ttl_value", ttl: @one_hour)
    Cachex.set(:bench_cache, "update_test", "update_value")

    use_state = get_opt("CACHEX_BENCH_STATE")
    use_trans = get_opt("CACHEX_BENCH_TRANSACTIONS")

    if use_trans do
      Cachex.Services.Overseer.update(:bench_cache, fn(state) ->
        %Cachex.Cache{ state | transactions: true }
      end)
    end

    cache = if use_state do
      Cachex.inspect!(:bench_cache, :state)
    else
      :bench_cache
    end

    headr = """

    Benching with state:        #{use_state}
    Benching with transactions: #{use_trans}
    """

    IO.puts(headr)

    { :ok, cache }
  end

  bench "count" do
    Cachex.count(bench_context)
    :ok
  end

  bench "decr" do
    Cachex.decr(bench_context, "decr_test")
    :ok
  end

  bench "del" do
    Cachex.del(bench_context, "del_test")
    :ok
  end

  bench "empty?" do
    Cachex.empty?(bench_context)
    :ok
  end

  bench "exists?" do
    Cachex.exists?(bench_context, "exists_test")
    :ok
  end

  bench "expire" do
    Cachex.expire(bench_context, "expire_test", @one_hour)
    :ok
  end

  bench "expire_at" do
    Cachex.expire_at(bench_context, "expire_at_test", @tomorrow)
    :ok
  end

  bench "get" do
    Cachex.get(bench_context, "get_test")
    :ok
  end

  bench "get_and_update" do
    Cachex.get_and_update(bench_context, "gad_test", &(&1))
    :ok
  end

  bench "incr" do
    Cachex.incr(bench_context, "incr_test")
    :ok
  end

  bench "keys" do
    Cachex.keys(bench_context)
    :ok
  end

  bench "persist" do
    Cachex.persist(bench_context, "persist_test")
    :ok
  end

  bench "refresh" do
    Cachex.refresh(bench_context, "refresh_test")
    :ok
  end

  bench "set" do
    Cachex.set(bench_context, "set_test", "set_value")
    :ok
  end

  bench "size" do
    Cachex.size(bench_context)
    :ok
  end

  bench "take" do
    Cachex.take(bench_context, "take_test")
    :ok
  end

  bench "ttl" do
    Cachex.ttl(bench_context, "ttl_test")
    :ok
  end

  bench "update" do
    Cachex.update(bench_context, "update_test", "update_value")
    :ok
  end

  defp get_opt(key),
    do: System.get_env(key) == "true"
end
