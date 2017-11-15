defmodule Cachex.RecordTest do
  use CachexCase

  # Record creation is handled by a single functions which detects things like
  # the correct expirations to set. There are three cases to verify - the first
  # being record creation without an expiration. Following that, we need to verify
  # that we can set a custom expiration, as well as have a default expiration
  # pulled back from the passed in state argument.
  test "creating a record" do
    # define our key and value
    key = "key"
    val = "val"

    # define our states, with and without a default TTL
    state1 = %Cachex.Cache{ }
    state2 = %Cachex.Cache{ state1 | default_ttl: 1000 }

    # create our three records
    record1 = Cachex.Record.create(state1, key, val)
    record2 = Cachex.Record.create(state2, key, val)
    record3 = Cachex.Record.create(state1, key, val, 2500)

    # retrieve the current time
    current = Cachex.Util.now()

    # all use the same validation
    validate = fn(record, exp) ->
      # break down the record
      { r_key, r_touch, r_exp, r_val } = record

      # validate the key, ttl and value
      assert(r_key == key)
      assert(r_exp == exp)
      assert(r_val == val)

      # touch time is a date, so we need to delta
      assert_in_delta(r_touch, current, 3)
    end

    # the first record has no expiration
    validate.(record1, nil)

    # the second record has a default TTL of 1000
    validate.(record2, 1000)

    # the third record has a custom expiry of 2500
    validate.(record3, 2500)
  end
end
