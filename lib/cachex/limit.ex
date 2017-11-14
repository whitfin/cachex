defmodule Cachex.Limit do
  @moduledoc false
  # This module defines the Limit struct used to signify any cache limits with
  # regards to the bounds of the cache. Currently this struct stores the maximum
  # amount of cache entries, a policy to use when evicting entries, and a percentage
  # of the cache to reclaim.

  # add a policy alias
  alias Cachex.Policy

  # internal limit struct
  defstruct [
    limit:   nil,               # the limit to apply (entry count)
    policy:  Policy.LRW,        # the module to handle
    reclaim: 0.1                # the amount of the cache to reclaim
  ]

  # our opaque type
  @opaque t :: %__MODULE__{ }

  # define limit types
  @type limit :: Limit.t
  @type limit_total :: number

  @doc """
  Parses an input into a Limit struct.

  Acceptable values are a preconstructed limit, or a maximum count. In the latter
  case, the LRW policy will be used with a 10% reclaim space.
  """
  def parse(%__MODULE__{ limit: limit, policy: policy, reclaim: reclaim }),
    do: parse_limit(limit, policy, reclaim)
  def parse(limit),
    do: parse_limit(limit)

  @doc """
  Converts a Limit struct to the required Hook form.

  Limits function as hooks inside a cache (at this point in time), and as such,
  this function is just sugar to do the conversion on a given Limit structure.
  """
  def to_hooks(%__MODULE__{ limit: nil }),
    do: []
  def to_hooks(%__MODULE__{ limit: limit, policy: policy, reclaim: reclaim }),
    do: [
      %Cachex.Hook{
        args: { limit, reclaim },
        module: policy,
        provide: [ :worker ],
        type: :post
      }
    ]

  # Internal parser for a Limit to ensure that we don't waste any cycles checking
  # the same constraints multiple times. We apply defaults for any values which
  # don't fit the necessary criteria.
  defp parse_limit(limit, policy \\ Policy.LRW, reclaim \\ 0.1) do
    %__MODULE__{
      limit:   v_parse(:limit,   limit,   &(is_number(&1) and &1 > 0)),
      policy:  v_parse(:policy,  policy,  &Policy.valid?/1),
      reclaim: v_parse(:reclaim, reclaim, &(is_number(&1) and &1 > 0 and &1 <= 1))
    }
  end

  # Internal value parser which falls back to using defaults in the scenario the
  # provided value is invalid based upon the provided condition.
  defp v_parse(key, val, condition),
    do: condition.(val) && val || Map.get(%__MODULE__{ }, key)

end
