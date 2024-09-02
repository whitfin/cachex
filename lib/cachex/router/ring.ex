defmodule Cachex.Router.Ring do
  @moduledoc """
  Routing implementation using a consistent hash ring.

  This router provides the most resilient routing for a distributed cache,
  due to being much more resilient to addition and removal of nodes in
  the cluster. Most distributed caches will end up using this router if
  they have the requirement to handle such cases.

  The core implementation of this router is provided by the Discord
  [library](https://github.com/discord/ex_hash_ring), so please see their
  repository for further details.
  """
  use Cachex.Router
  import Cachex.Spec

  # core aliases
  alias Cachex.Options
  alias Cachex.Router
  alias ExHashRing.Ring

  @doc """
  Initialize a ring routing state for a cache.

  ## Options

    * `:monitor`

      This option specifies whether to monitor Erlang `:nodeup` and `:nodedown`
      events and scale this ring to add/remove nodes dynamically. This defaults
      to `false`, but if you're using this router it's likely you want this enabled.

    * `:monitor_type`

      The type of nodes to listen for and dynamically add to the internal ring.
      This defaults to `:all`, but can be any value accepted by the OTP function
      `:net_kernel.monitor_nodes/2`.

    * `:nodes`

      The `:nodes` option allows a user to provide a list of nodes to treat
      as a cluster. If this is not provided, the cluster will be inferred
      by using `Node.self/1` and `Node.list/2`.

  """
  @spec init(cache :: Cachex.Spec.cache(), options :: Keyword.t()) ::
          ExHashRing.Ring.ring()
  def init(cache(name: name), _options),
    do: name(name, :router)

  @doc """
  Retrieve the list of nodes from a ring routing state.
  """
  @spec nodes(ring :: Ring.t()) :: {:ok, [atom]}
  def nodes(ring) do
    with {:ok, nodes} <- Ring.get_nodes(ring) do
      nodes
    end
  end

  @doc """
  Route a key to a node in a ring routing state.
  """
  @spec route(ring :: Ring.t(), key :: any) :: {:ok, atom}
  def route(ring, key) do
    with {:ok, node} <- Ring.find_node(ring, key) do
      node
    end
  end

  @doc """
  Create a child specification to back a ring routing state.
  """
  @spec spec(cache :: Cachex.Spec.cache(), options :: Keyword.t()) ::
          Supervisor.child_spec()
  def spec(cache(name: name), options) do
    delegate_opts = [
      name: name(name, :router),
      nodes: Keyword.get_lazy(options, :nodes, &Router.connected/0),
      monitor: Options.get(options, :monitor, &is_boolean/1, false),
      monitor_type: Options.get(options, :monitor_type, &is_atom/1, :all),
      replicas: 128
    ]

    delegate_spec = [
      %{
        id: Ring,
        type: :worker,
        restart: :permanent,
        start: {Ring, :start_link, [delegate_opts]}
      },
      %{
        id: __MODULE__.Monitor,
        type: :worker,
        restart: :permanent,
        start: {GenServer, :start_link, [__MODULE__.Monitor, delegate_opts]}
      }
    ]

    delegate_spec
  end
end
