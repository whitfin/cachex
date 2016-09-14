defmodule Cachex.PolicyTest do
  use CachexCase

  # This tests very little (as the module is small), just a list of known and
  # unknown policies. Right now there are very few, and the Policy module is
  # only used for determining valid policy.
  test "checking a valid policy" do
    # define our known policies
    known = [
      Cachex.Policy.LRW
    ]

    # define our unknown policies
    unknown = [
      Cachex.Policy,
      Cachex.Policy.Yolo
    ]

    # ensure our known policies exist
    Enum.each(known, fn(policy) ->
      assert(Cachex.Policy.valid?(policy))
    end)

    # ensure our unknown policies do not
    Enum.each(unknown, fn(policy) ->
      refute(Cachex.Policy.valid?(policy))
    end)
  end

end
