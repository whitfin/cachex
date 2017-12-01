defmodule Cachex.Actions.Exists do
  @moduledoc """
  Command module to allow checking for entry existence.

  This is very straightfoward, but is a little more than an `:ets.member/2`
  call as we also need to validate expiration time to stay consistent.
  """
  alias Cachex.Actions

  # add required macros
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Checks whether an entry exists in a cache.

  This is a little more involved than a straight ETS call, as we need to take
  the expiration time of the entry into account. As such, we call via the main
  `Cachex.Actions` module and just cast the result to a boolean.
  """
  defaction exists?(cache() = cache, key, options),
    do: { :ok, !!Actions.read(cache, key) }
end
