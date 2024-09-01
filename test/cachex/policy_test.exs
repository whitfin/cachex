defmodule Cachex.PolicyTest do
  use Cachex.Test.Case

  test "default policy implementations" do
    assert __MODULE__.DefaultPolicy.hooks(limit()) == []
  end

  defmodule DefaultPolicy,
    do: use(Cachex.Policy)
end
