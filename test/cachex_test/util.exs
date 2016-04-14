defmodule CachexTest.Util do
  use PowerAssert

  alias Cachex.Util

  test "util.now/0 generates a UTC timestamp" do
    epoch = {{1970, 1, 1}, {0, 0, 0}}
    calendar = :calendar.datetime_to_gregorian_seconds(epoch)

    now =
      :calendar.universal_time()
      |> :calendar.datetime_to_gregorian_seconds
      |> -(calendar)

    assert(div(Util.now(), 1000) == now)
  end

  test "util.error/1 wraps a value in an error tuple" do
    assert(Util.error(:test) == { :error, :test })
  end

  test "util.ok/1 wraps a value in an ok tuple" do
    assert(Util.ok(:test) == { :ok, :test })
  end

  test "util.noreply/1 wraps a state in a noreply tuple" do
    assert(Util.noreply(:test) == { :noreply, :test })
  end

  test "util.noreply/2 swallows a pipe and wraps a state in a noreply tuple" do
    assert(Util.noreply(:value, :test) == { :noreply, :test })
  end

  test "util.reply/2 wraps a state and value in a reply tuple" do
    assert(Util.reply(:value, :test) == { :reply, :value, :test })
  end

  test "util.create_node_name/1 generates a node name on the local host" do
    nodename = Util.create_node_name("my_name")
    hostname = :inet.gethostname |> elem(1) |> to_string

    assert(to_string(nodename) == "my_name@#{hostname}")
  end

  test "util.create_node_name/1 works with an atom name" do
    nodename = Util.create_node_name(:my_name)
    hostname = :inet.gethostname |> elem(1) |> to_string

    assert(to_string(nodename) == "my_name@#{hostname}")
  end

  test "util.create_node_name/1 generates a node name on a given host" do
    nodename = Util.create_node_name("my_name", "localhost")
    assert(to_string(nodename) == "my_name@localhost")
  end

  test "util.create_record/3 generates records with no expiration" do
    { cache, key, date, ttl, value } = Util.create_record(%Cachex.Worker{ "cache": :test }, "key", "value")

    assert(cache == :test)
    assert(key == "key")
    assert_in_delta(date, Util.now(), 2)
    assert(value == "value")
    assert(ttl == nil)
  end

  test "util.create_record/3 generates records with a default expiration" do
    { cache, key, date, ttl, value } = Util.create_record(%Cachex.Worker{
      "cache": :test,
      "options": %{
        "default_ttl": :timer.seconds(5)
      }
    }, "key", "value")

    assert(cache == :test)
    assert(key == "key")
    assert_in_delta(date, Util.now(), 2)
    assert(value == "value")
    assert(ttl == 5000)
  end

  test "util.create_record/4 generates records with a custom expiration" do
    { cache, key, date, ttl, value } = Util.create_record(%Cachex.Worker{ "cache": :test }, "key", "value", 5000)

    assert(cache == :test)
    assert(key == "key")
    assert_in_delta(date, Util.now(), 2)
    assert(value == "value")
    assert(ttl == 5000)
  end

  test "util.create_truthy_result/2 returns an ok(true) tuple when truthy" do
    result = Util.create_truthy_result("test")
    assert(result == { :ok, true })
  end

  test "util.create_truthy_result/2 returns an error(false) tuple when falsey" do
    result = Util.create_truthy_result(nil)
    assert(result == { :error, false })
  end

  test "util.get_fallback_function/2 returns a custom fallback if available" do
    state = %{
      "cache": :test,
      "options": %{
        "default_fallback": fn() ->
          :error
        end
      }
    }

    input_fun = fn() ->
      :ok
    end

    fun = Util.get_fallback_function(state, input_fun)
    assert(fun == input_fun)
  end

  test "util.get_fallback_function/1 returns a default fallback if available" do
    input_fun = fn() ->
      :ok
    end

    state = %{
      "cache": :test,
      "options": %{
        "default_fallback": input_fun
      }
    }

    fun = Util.get_fallback_function(state)
    assert(fun == input_fun)
  end

  test "util.get_fallback_function/1 returns nil if no function is available" do
    state = %{
      "cache": :test,
      "options": %{
        "default_fallback": 1
      }
    }

    fun = Util.get_fallback_function(state)
    assert(fun == nil)
  end

  test "util.get_opt_function/3 defaults to returning nil" do
    assert(Util.get_opt_function([], :test) == nil)
  end

  test "util.get_opt_list/3 defaults to returning nil" do
    assert(Util.get_opt_list([], :test) == nil)
  end

  test "util.get_opt_number/3 defaults to returning nil" do
    assert(Util.get_opt_number([], :test) == nil)
  end

  test "util.get_opt_positive/3 defaults to returning nil" do
    assert(Util.get_opt_positive([], :test) == nil)
  end

  test "util.get_opt/4 returns options from a map" do
    input_fun = fn -> :ok end
    val = Util.get_opt([fun: input_fun], :fun, fn -> :error end, &(is_function/1))
    assert(val == input_fun)
  end

  test "util.get_opt/4 does not return options not fitting a criteria" do
    val = Util.get_opt([fun: 1], :fun, nil, &(is_function/1))
    assert(val == nil)
  end

  test "util.get_opt/4 returns default values if conditions aren't met" do
    val = Util.get_opt([fun: 1], :fun, 50, &(is_function/1))
    assert(val == 50)
  end

  test "util.get_opt/4 handles crashing functions as falsey" do
    val = Util.get_opt([fun: 1], :fun, 50, &(byte_size(&1) == 8))
    assert(val == 50)
  end

  test "util.handle_transaction/1 formats transaction results into tuples" do
    assert(Util.handle_transaction({ :atomic, { :error, :test } }) == { :error, :test })
    assert(Util.handle_transaction({ :atomic, { :ok, :test } }) == { :ok, :test })
    assert(Util.handle_transaction({ :atomic, { :loaded, :test } }) == { :loaded, :test })
    assert(Util.handle_transaction({ :atomic, :test }) == { :ok, :test })
    assert(Util.handle_transaction({ :aborted, :test }) == { :error, :test })
  end

  test "util.handle_transaction/2 formats transaction results into tuples" do
    assert(Util.handle_transaction({ :atomic, { :ok, :test } }, :test) == { :ok, :test })
    assert(Util.handle_transaction({ :aborted, :test }, :arg) == { :error, :test })
  end

  test "util.has_expired?/2 determines if a date and ttl has passed" do
    assert(Util.has_expired?(Util.now(), -5000))
    refute(Util.has_expired?(Util.now(), 5000))
    refute(Util.has_expired?(nil, 5000))
    refute(Util.has_expired?(5000, nil))
    refute(Util.has_expired?(nil, nil))
  end

  test "util.has_arity?/2 determines if a function has a given arity" do
    assert(Util.has_arity?(&(&1), 1))
    refute(Util.has_arity?(&(&1), 2))
  end

  test "util.has_arity?/2 determines if a function has any of the given arities" do
    assert(Util.has_arity?(&(&1), [3,2,1]))
    refute(Util.has_arity?(&(&1), [3,2]))
  end

  test "util.last_of_tuple/1 returns the last value in a tuple" do
    assert(Util.last_of_tuple({ :one, :two, :three }) == :three)
    assert(Util.last_of_tuple({}) == nil)
  end

  test "util.list_to_tuple/1 converts a list to a tuple" do
    assert(Util.list_to_tuple([ :one, :two, :three ]) == { :one, :two, :three })
    assert(Util.list_to_tuple([]) == {})
  end

  test "util.retrieve_all_rows/1 returns a select on all rows" do
    [ { variables, condition, result } ] =
      true
      |> Util.retrieve_all_rows

    assert(variables == { :"_", :"$1", :"$2", :"$3", :"$4" })
    assert(result == [ true ])

    [ { type, cond1, { sign, sum, date } } ] = condition

    assert(type == :orelse)
    assert(cond1 == { :"==", :"$3", nil })
    assert(sign == :">")
    assert(sum == { :"+", :"$2", :"$3" })
    assert_in_delta(date, Util.now, 2)
  end

  test "util.stats_for_cache/1 converts a cache name to a stats name" do
    assert(Util.stats_for_cache(:cache) == :cache_stats)
  end

end
