defmodule Cachex.Provision do
  @moduledoc """
  Module controlling provisioning behaviour definitions.

  This module defines the provisioning implementation for Cachex, allowing
  components such as hooks and warmers to tap into state changes in the cache
  table. By implementing `handle_provision/2` these components can be provided
  with new versions of state as they're created.
  """

  #############
  # Behaviour #
  #############

  @doc """
  Returns an enumerable of provisions this implementation requires.

  The current provisions available are:

    * `cache` - a cache instance used to make cache calls with lower overhead.

  This should always return an enumerable of atoms; in the case of no required
  provisions an empty enumerable should be returned.
  """
  @callback provisions :: [type :: atom]

  @doc """
  Handles a provisioning call.

  The provided argument will be a Tuple dictating the type of value being
  provisioned along with the value itself. This can be used to listen on
  states required for hook executions (such as cache records).
  """
  @callback handle_provision(
              provison :: {type :: atom, value :: any},
              state :: any
            ) :: {:ok, state :: any}

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      # use the provision behaviour
      @behaviour Cachex.Provision

      #################
      # Configuration #
      #################

      @doc false
      def provisions,
        do: []

      # config overrides
      defoverridable provisions: 0

      #########################
      # Notification Handlers #
      #########################

      @doc false
      def handle_provision(provision, state),
        do: {:ok, state}

      # listener override
      defoverridable handle_provision: 2

      ##########################
      # Private Implementation #
      ##########################

      @doc false
      def handle_info({:cachex_provision, provision}, state) do
        {:ok, new_state} = handle_provision(provision, state)
        {:noreply, new_state}
      end
    end
  end
end
