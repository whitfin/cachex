defmodule Cachex.Policy do
  @moduledoc """
  Module controlling policy behaviour definitions.

  This module purely exposes the behaviour and convenience macros for
  creating a custom policy. It's used internally be `Cachex.Policy.LRW`
  and provides very little more than an interface to adhere to.
  """
  import Cachex.Spec

  #############
  # Behaviour #
  #############

  @doc """
  Returns any hook definitions required for this policy.
  """
  @callback hooks(Spec.limit()) :: [Spec.hook()]

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      # include the behaviour
      @behaviour Cachex.Policy

      @doc false
      def hooks(_limit),
        do: []

      # all can be overridden
      defoverridable hooks: 1
    end
  end
end
