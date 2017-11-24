defmodule Cachex.Policy do
  @moduledoc false
  # This module contains the definition of the Policy behaviour.
  import Cachex.Spec

  @doc """
  Returns any hook definitions required for this policy.
  """
  @callback hooks(Spec.limit) :: [ Cachex.Hook.t ]

  @doc """
  Returns an optional child spec to start for this policy.
  """
  @callback children(Spec.limit) :: Supervisor.Spec.spec

  @doc """
  Returns the Supervisor strategy for this policy.
  """
  @callback strategy :: Supervisor.Spec.strategy

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      # include the behaviour
      @behaviour Cachex.Policy

      @doc false
      def hooks(_limit),
        do: []

      @doc false
      def children(_limit),
        do: []

      @doc false
      def strategy,
        do: :one_for_one

      # all can be overridden
      defoverridable [
        hooks: 1,
        children: 1,
        strategy: 0
      ]
    end
  end
end
