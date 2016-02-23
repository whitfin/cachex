defmodule CachexTest do
  use ExUnit.Case

  @test_cache :my_test_cache
  @test_file "/tmp/cache_test_file"

  setup do
    Cachex.start_link([name: @test_cache, record_stats: true])
    Cachex.clear!(@test_cache)
    Enum.each(1..1000, fn(x) ->
      Cachex.set!(@test_cache, "key#{x}", "value#{x}")
    end)
    File.rm_rf!(@test_file)
    :ok
  end

  test "deft macro cannot accept non-atom caches" do
    assert_raise RuntimeError, "Invalid cache name provided, got: \"test\"", fn ->
      Cachex.get!("test", "key")
    end
  end

  test "specific key retrieval" do
    Enum.each(1..1000, fn(x) ->
      assert(Cachex.get!(@test_cache, "key#{x}") == "value#{x}")
    end)
  end

  test "key deletion" do
    Enum.each(1..1000, fn(x) ->
      assert(Cachex.del!(@test_cache, "key#{x}"))
      assert(Cachex.size!(@test_cache) == 1000 - x)
    end)
  end

  test "empty checking" do
    assert(!Cachex."empty?!"(@test_cache))
    assert(Cachex.clear!(@test_cache))
    assert(Cachex."empty?!"(@test_cache))
  end

  test "key exists" do
    Enum.each(1..1000, fn(x) ->
      assert(Cachex."exists?!"(@test_cache, "key#{x}"))
    end)
    assert(!Cachex."exists?!"(@test_cache, "key1001"))
  end

  test "key increment" do
    assert(Cachex.set!(@test_cache, "key", 1))
    assert(Cachex.incr!(@test_cache, "key") == 2)
    assert(Cachex.incr!(@test_cache, "key", 2) == 4)
    assert(Cachex.incr!(@test_cache, "keyX", 5, 5) == 10)
  end

  test "key list retrieval" do
    keys = Cachex.keys!(@test_cache)
    assert(keys |> Enum.count == 1000)
  end

  test "key taking" do
    Enum.each(1..1000, fn(x) ->
      assert(Cachex.take!(@test_cache, "key#{x}") == "value#{x}")
      assert(Cachex.size!(@test_cache) == 1000 - x)
    end)
  end

  test "key being set" do
    assert(Cachex.set!(@test_cache, "key", "value"))
    assert(Cachex.get!(@test_cache, "key") == "value")
  end

  test "size retrieval" do
    assert(Cachex.size!(@test_cache) == 1000)
  end

  test "clearing" do
    assert(Cachex.size!(@test_cache) == 1000)
    assert(Cachex.clear!(@test_cache))
    assert(Cachex.size!(@test_cache) == 0)
  end

end
