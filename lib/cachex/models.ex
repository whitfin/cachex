defmodule Cachex.Models do
  @moduledoc false
  # Model definitions around the Erlang Record syntax.
  import Record

  # hook pairings for cache internals
  defrecord :hooks, pre: [], post: []
end
