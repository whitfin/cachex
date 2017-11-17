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
    reclaim: 0.1,               # the amount of the cache to reclaim
    options: []                 # arbitrary options to pass to the hook
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
  def parse(%__MODULE__{ } = mod) do
    with :ok <- v_parse(mod,   :limit, &(is_nil(&1) || (is_number(&1) and &1 > 0))),
         :ok <- v_parse(mod,  :policy, &Policy.valid?/1),
         :ok <- v_parse(mod, :reclaim, &(is_number(&1) and &1 > 0 and &1 <= 1)),
         :ok <- v_parse(mod, :options, &Keyword.keyword?/1),
     do: { :ok, mod }
  end
  def parse(limit),
    do: parse(%__MODULE__{ limit: limit })

  @doc """
  Converts a Limit struct to the required Hook form.

  Limits function as hooks inside a cache (at this point in time), and as such,
  this function is just sugar to do the conversion on a given Limit structure.
  """
  def to_hooks(%__MODULE__{ limit: nil }),
    do: []
  def to_hooks(%__MODULE__{ policy: policy } = limit),
    do: [
      %Cachex.Hook{
        args: limit,
        module: policy,
        provide: [ :cache ],
        type: :post
      }
    ]

  # Internal value parser which falls back to using defaults in the scenario the
  # provided value is invalid based upon the provided condition.
  defp v_parse(mod, key, condition) do
    value = Map.fetch!(mod, key)
    case condition.(value) do
      true  -> :ok
      false -> { :error, :invalid_limit }
    end
  end
end
