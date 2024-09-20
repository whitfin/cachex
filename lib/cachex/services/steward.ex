defmodule Cachex.Services.Steward do
  @moduledoc """
  Service module overseeing cache provisions.

  This module controls state provision to Cachex components, such as hooks
  and warmers. In previous versions of Cachex provisions were handled under
  the `Cachex.Hook` behaviour, but the introduction of warmers meant that it
  should be handled in a separate location.

  This service module will handle the provision of state to relevant components
  attached to a cache, without the caller having to think about it.
  """
  import Cachex.Spec
  alias Cachex.Services

  # recognised
  @provisions [
    :cache
  ]

  ##############
  # Public API #
  ##############

  @doc """
  Provides an state pair to relevant components.

  This will send updated state to all interest components, but does not
  wait for a response before returning. As provisions are handled in a
  base implementation, we can be sure of safe implementation here.
  """
  @spec provide(Cachex.t(), {atom, any}) :: :ok
  def provide(cache() = cache, {key, _} = provision) when key in @provisions do
    cache(hooks: hooks(pre: pre, post: post)) = cache
    cache(warmers: warmers) = cache

    services =
      cache
      |> Services.services()
      |> Enum.filter(&filter_services/1)

    provisioned =
      services
      |> Enum.concat(pre)
      |> Enum.concat(post)
      |> Enum.concat(warmers)
      |> Enum.map(&map_names/1)

    for {name, mod} <- provisioned, key in mod.provisions() do
      send(name, {:cachex_provision, provision})
    end
  end

  ##############
  # Private API #
  ##############

  # Map a hook into the name and module tuple
  defp map_names(hook(name: name, module: module)),
    do: {name, module}

  # Map a warmer into the name and module tuple
  defp map_names(warmer(name: name, module: module)),
    do: {name, module}

  # Map a service into the name and module tuple
  defp map_names({module, name, _tag, _id}),
    do: {name, module}

  # Filter out service modules if they don't have provisions
  defp filter_services({module, _name, _tag, _id}) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> Enum.member?([Cachex.Provision])
  end
end
