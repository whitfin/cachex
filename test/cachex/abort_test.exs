defmodule Cachex.AbortTest do
  use PowerAssert, async: false

  test "abort does nothing when not in a transaction" do
    assert(Cachex.abort(%Cachex.State{}, :exit) == { :ok, false })
  end

  test "abort exits with a given reason when in a transaction" do
    res = :mnesia.transaction(fn ->
      Cachex.abort(%Cachex.State{}, :yolo)
    end)
    assert(res == { :aborted, :yolo })
  end

end
