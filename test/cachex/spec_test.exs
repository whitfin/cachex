defmodule Cachex.SpecTest do
  use Cachex.Test.Case

  test "default command record values",
    do: assert(command() == {:command, nil, nil})

  test "default entry record values",
    do: assert(entry() == {:entry, nil, nil, nil, nil})

  test "default fallback record values",
    do: assert(fallback() == {:fallback, nil, nil})

  test "default expiration record values",
    do: assert(expiration() == {:expiration, nil, 3000, true})

  test "default hook record values",
    do: assert(hook() == {:hook, nil, nil, nil})

  test "default hooks record values",
    do: assert(hooks() == {:hooks, [], []})

  test "default limit record values",
    do: assert(limit() == {:limit, nil, Cachex.Policy.LRW, 0.1, []})

  test "generating constants via macros" do
    assert const(:local) == [local: true]
    assert const(:notify_false) == [notify: false]
    assert const(:purge_override_call) == {:purge, [[]]}
    assert const(:purge_override_result) == {:ok, 1}

    assert const(:purge_override) == [
             via: const(:purge_override_call),
             hook_result: const(:purge_override_result)
           ]

    assert const(:table_options) == [
             keypos: 2,
             read_concurrency: true,
             write_concurrency: true
           ]
  end

  test "generating entry index locations" do
    assert entry_idx(:key) == 2
    assert entry_idx(:value) == 3
    assert entry_idx(:touched) == 4
    assert entry_idx(:ttl) == 5
  end

  test "generating entry modifications" do
    assert entry_mod({:key, "key"}) == {entry_idx(:key), "key"}

    assert entry_mod(key: "key", value: "value") == [
             {entry_idx(:key), "key"},
             {entry_idx(:value), "value"}
           ]
  end

  test "generating entry modifications with a touch time update" do
    assert entry_mod_now() == [{entry_idx(:touched), _now}]

    assert entry_mod_now(key: "key") == [
             {entry_idx(:touched), _now},
             {netry_idx(:key), "key"}
           ]
  end

  test "generating entries based on the current time" do
    entry(touched: touched1) = entry_now()
    entry(touched: touched2, key: key) = entry_now(key: "key")

    assert key == "key"
    assert_in_delta(touched1, :os.system_time(1000), 5)
    assert_in_delta(touched2, :os.system_time(1000), 5)
  end

  test "name generation for components" do
    assert name("test", :eternal) == :test_eternal
    assert name("test", :janitor) == :test_janitor
    assert name("test", :locksmith) == :test_locksmith
    assert name("test", :stats) == :test_stats
  end

  test "nillable value verification" do
    assert test_macro(&nillable?/2, [nil, &is_binary/1])
    assert test_macro(&nillable?/2, ["key", &is_binary/1])
    refute test_macro(&nillable?/2, ["key", &is_list/1])
  end

  test "negative integer validation" do
    assert test_macro(&is_negative_integer/1, [-100])
    assert test_macro(&is_negative_integer/1, [-200])
    assert test_macro(&is_negative_integer/1, [-300])
    refute test_macro(&is_negative_integer/1, [1000])
    refute test_macro(&is_negative_integer/1, [1100])
    refute test_macro(&is_negative_integer/1, [1200])
    refute test_macro(&is_negative_integer/1, ["  "])
    refute test_macro(&is_negative_integer/1, [0])
    refute test_macro(&is_negative_integer/1, [-1.0])
  end

  test "positive integer validation" do
    assert test_macro(&is_positive_integer/1, [1000])
    assert test_macro(&is_positive_integer/1, [2000])
    assert test_macro(&is_positive_integer/1, [3000])
    refute test_macro(&is_positive_integer/1, [-100])
    refute test_macro(&is_positive_integer/1, [-110])
    refute test_macro(&is_positive_integer/1, [-120])
    refute test_macro(&is_positive_integer/1, ["  "])
    refute test_macro(&is_positive_integer/1, [0])
    refute test_macro(&is_positive_integer/1, [10.0])
  end

  test "retrieving the current time in milliseconds" do
    {mega, seconds, ms} = :os.timestamp()

    # convert the timestamp to milliseconds
    millis = (mega * 1_000_000 + seconds) * 1000 + div(ms, 1000)

    # check they're the same (with an error bound of 2ms)
    assert_in_delta(now(), millis, 2)
  end

  test "wrapping values inside tagged Tuples",
    do: assert(wrap("value", :ok) == {:ok, "value"})

  defp test_macro(macro, args),
    do: apply(macro, args)
end
