defmodule Cachex.PolicyTest do
  use PowerAssert, async: false

  test "checking a valid policy" do
    assert(Cachex.Policy.valid?(Cachex.Policy.LRW))
  end

  test "checking an invalid policy" do
    refute(Cachex.Policy.valid?(Cachex.Policy.Yolo))
  end

end
