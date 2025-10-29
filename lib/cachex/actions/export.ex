defmodule Cachex.Actions.Export do
  @moduledoc false
  # Command module to allow exporting all cache entries as a list.
  #
  # This command is extremely expensive as it turns the entire cache table into
  # a list, and so should be used sparingly. It's provided purely because it's
  # the backing implementation of the `Cachex.save/3` command.
  alias Cachex.Query

  # add required imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves all cache entries as a list.

  This action should only be used in the case of exports and/or debugging, due
  to the memory overhead involved, as well as the large concatenations.
  """
  def execute(cache() = cache, _options) do
    query = Query.build()
    options = const(:local) ++ const(:notify_false)

    case Cachex.stream(cache, query, options) do
      {:error, _reason} = error ->
        error

      stream ->
        Enum.to_list(stream)
    end
  end
end
