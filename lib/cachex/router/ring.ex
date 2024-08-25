defmodule Cachex.Router.Ring do
  @moduledoc """
  Routing implementation using a consistent hash ring.

  This router provides the most resilient routing for a distributed cache,
  due to being much more resilient to addition and removal of nodes in
  the cluster. Most distributed caches will end up using this router if
  they have the requirement to handle such cases.

  The implementation inside this router is entirely provided by the
  [libring](https://github.com/bitwalker/libring) library. As such the
  initialization of this router will accept all options available when
  calling `HashRing.Managed.new/2`.

  The documentation (pinned at the version used by Cachex) can be found
  [here](https://hexdocs.pm/libring/1.6.0/HashRing.Managed.html#new/2).
  """
  use Cachex.Router
  import Cachex.Spec

  @doc """
  Initialize a ring routing state for a cache.

  To see the list of options supported for this call, please visit the `libring`
  [documentation](https://hexdocs.pm/libring/1.6.0/HashRing.Managed.html#new/2).
  """
  @spec init(cache :: Cachex.Spec.cache(), options :: Keyword.t()) ::
          HashRing.Managed.ring()
  def init(cache(name: name), _options),
    do: name

  @doc """
  Retrieve the list of nodes from a  routing state.
  """
  @spec nodes(ring :: HashRing.Managed.ring()) :: [atom]
  defdelegate nodes(ring), to: HashRing.Managed

  @doc """
  Route a key to a node in a ring routing state.
  """
  @spec route(ring :: HashRing.Managed.ring(), key :: any) :: atom
  defdelegate route(ring, key), to: HashRing.Managed, as: :key_to_node

  @doc """
  Create a child specification to back a ring routing state.
  """
  @spec spec(cache :: Cachex.Spec.cache(), options :: Keyword.t()) ::
          Supervisor.child_spec()
  def spec(cache(name: name), options),
    do: [
      %{
        id: name,
        type: :worker,
        restart: :permanent,
        start: {HashRing.Worker, :start_link, [[{:name, name} | options]]}
      }
    ]
end
