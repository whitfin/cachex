# defmodule Cachex.Router.Ring do
#   use Cachex.Router

#   def init(nodes, _options \\ []) do
#     ring = HashRing.new()
#     ring = HashRing.add_nodes(ring, nodes)
#     ring
#   end

#   defdelegate nodes(ring), to: HashRing, as: :nodes
#   defdelegate route(ring, key), to: HashRing, as: :key_to_node
#   defdelegate attach(ring, node), to: HashRing, as: :add_node
#   defdelegate detach(ring, node), to: HashRing, as: :remove_node
# end
