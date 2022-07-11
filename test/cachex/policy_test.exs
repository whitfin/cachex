defmodule Cachex.PolicyTest do
  use CachexCase

  test "default policy implementations" do
    # validate each default implementation provided by __using__
    assert __MODULE__.DefaultPolicy.strategy() == :one_for_one
    assert __MODULE__.DefaultPolicy.hooks(limit()) == []
    assert __MODULE__.DefaultPolicy.child_spec(limit()) == []
  end

  defmodule DefaultPolicy,
    do: use(Cachex.Policy)
end
