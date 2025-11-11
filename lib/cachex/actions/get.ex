defmodule Cachex.Actions.Get do
  @moduledoc false
  # Command module to enable basic retrieval of cache entries.
  #
  # This command provides very little over the raw read actions provided by the
  # `Cachex.Actions` module, as most of the heavy lifting is done in there. The
  # only modification made is that the value is extracted, rather than returning
  # the entire entry.
  alias Cachex.Actions

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves a value from inside the cache.
  """
  def execute(cache() = cache, key, default, _options) do
    case Actions.read(cache, key) do
      entry(value: value) ->
        value

      nil ->
        default
    end
  end
end
