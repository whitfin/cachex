defmodule Cachex.WorkerTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "worker is able to return internal state", state do
    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Local)
    assert(worker.cache == state.cache)
    assert(worker.options == %Cachex.Options{
      cache: state.cache,
      default_fallback: nil,
      default_ttl: nil,
      ets_opts: [
        read_concurrency: true,
        write_concurrency: true
      ],
      fallback_args: [],
      nodes: [node()],
      post_hooks: [],
      pre_hooks: [],
      remote: false,
      ttl_interval: nil
    })
  end

end
