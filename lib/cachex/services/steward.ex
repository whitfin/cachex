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
  @spec provide(Cachex.Spec.cache(), {atom, any}) :: :ok
  def provide(cache() = cache, {key, _} = provision) when key in @provisions do
    cache(hooks: hooks(pre: pre_hooks, post: post_hooks)) = cache
    cache(warmers: warmers) = cache

    hook_pairs =
      pre_hooks
      |> Enum.concat(post_hooks)
      |> Enum.map(fn hook(module: mod, name: name) -> {name, mod} end)

    warmer_pairs =
      warmers
      |> Enum.map(fn warmer(module: mod) -> {mod, mod} end)

    warmer_pairs
    |> Enum.concat(hook_pairs)
    |> Enum.filter(fn {_, mod} -> key in mod.provisions() end)
    |> Enum.each(fn {name, _} -> send(name, {:cachex_provision, provision}) end)
  end
end
