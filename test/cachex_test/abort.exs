defmodule CachexTest.Abort do
  use PowerAssert

  test "abort does nothing when not in a transaction" do
    assert(Cachex.abort(%Cachex.Worker{}, :exit) == { :ok, false })
  end

  test "abort exits with a given reason when in a transaction" do
    res = :mnesia.transaction(fn ->
      Cachex.abort(%Cachex.Worker{}, :yolo)
    end)
    assert(res == { :aborted, :yolo })
  end

end
