defmodule Cachex.Policy do
  @moduledoc false
  # This module contains grace functions around internal eviction policies.
  # Currently very little exists in here beyond a centralized list of known modules
  # which can act as eviction policies when using inside a cache Limit.

  # our known policies
  @policies [ Cachex.Policy.LRW ]

  @doc """
  Returns whether a policy is known or not.
  """
  def valid?(policy), do: policy in @policies

end
