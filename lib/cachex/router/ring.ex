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

  #############
  # Behaviour #
  #############

  @doc """
  Initialize a ring routing state for a cache.

  ## Options

    * `:nodes`

      The `:nodes` option allows a user to provide a list of nodes to treat
      as a cluster. If this is not provided, the cluster will be inferred
      by using `Node.self/0` and `Node.list/1`.

    * `:monitor`

      This option specifies whether to monitor Erlang `:nodeup` and `:nodedown`
      events and scale this ring to add/remove nodes dynamically. This defaults
      to `false`, but if you're using this router it's likely you want this enabled.

    * `:monitor_excludes`

      This option allows the developer to provide a list of patterns to exclude
      nodes from joining automatically when monitoring is enabled. Patterns can be
      provided as either binaries or Regex.

    * `:monitor_includes`

      This option allows the developer to provide a list of patterns to validate
      nodes before allowing them to join the ring. Patterns can be provided as
      either binaries or Regex.

    * `:monitor_type`

      The type of nodes to listen for and dynamically add to the internal ring.
      This defaults to `:all`, but can be any value accepted by the OTP function
      `:net_kernel.monitor_nodes/2`.

  """
  @spec init(cache :: Cachex.t(), options :: Keyword.t()) :: Ring.ring()
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
  @spec spec(cache :: Cachex.t(), options :: Keyword.t()) ::
          Supervisor.child_spec()
  def spec(cache(name: name), options) do
    name = name(name, :router)

    monitor = Options.get(options, :monitor, &is_boolean/1, false)
    monitor_type = Options.get(options, :monitor_type, &is_atom/1, :all)

    monitor_includes = Options.get(options, :monitor_includes, &is_list/1, [])

    monitor_excludes =
      Options.get(options, :monitor_excludes, &is_list/1, [
        ~r/^remsh.*$/,
        ~r/^rem-.*$/
      ])

    nodes =
      options
      |> Keyword.get_lazy(:nodes, &Router.connected/0)
      |> Enum.filter(&included?(&1, monitor_includes, monitor_excludes))

    options = [
      name: name,
      nodes: nodes,
      monitor: monitor,
      monitor_type: monitor_type,
      monitor_includes: monitor_includes,
      monitor_excludes: monitor_excludes,
      replicas: 128
    ]

    [
      %{
        id: Ring,
        type: :worker,
        restart: :permanent,
        start: {Ring, :start_link, [options]}
      },
      %{
        id: __MODULE__.Monitor,
        type: :worker,
        restart: :permanent,
        start: {GenServer, :start_link, [__MODULE__.Monitor, options]}
      }
    ]
  end

  ##############
  # Public API #
  ##############

  @doc """
  Returns whether a node is included given the provided patterns.
  """
  @spec included?(
          node :: binary() | node(),
          includes :: [binary() | Regex.t()],
          excludes :: [binary() | Regex.t()]
        ) :: boolean()
  def included?(_node, [], []),
    do: true

  # When the node provided is an atom, convert it to a binary
  def included?(node, includes, excludes) when is_atom(node) do
    node
    |> Atom.to_string()
    |> included?(includes, excludes)
  end

  # When no includes are provided, test the exclude list
  def included?(node, [], excludes),
    do: !test_node(node, excludes)

  # When no excludes are provided, test the include list
  def included?(node, includes, []),
    do: test_node(node, includes)

  # When both are provided, test one then the other
  def included?(node, includes, excludes) do
    included? = included?(node, includes, [])
    excluded? = not included?(node, [], excludes)

    cond do
      excluded? and included? -> true
      excluded? -> false
      included? -> true
      true -> false
    end
  end

  ###############
  # Private API #
  ###############

  # Compare an input node name against a list of patterns and returns
  # true if any of the patterns match the provided node value.
  defp test_node(node, patterns) do
    Enum.any?(patterns, fn
      ^node ->
        true

      pattern when is_binary(pattern) ->
        case Regex.compile(pattern) do
          {:ok, regex} ->
            Regex.match?(regex, node)

          {:error, _reason} ->
            false
        end

      %Regex{} = pattern ->
        Regex.match?(pattern, node)

      _other ->
        false
    end)
  end
end
