defmodule CachexCase.ForwardHook do
  @moduledoc false
  # This module provides a Cachex hook interface which simply forwards all messages
  # to the calling process.
  #
  # This is useful to validate that messages sent actually do arrive as intended,
  # without having to trust assertions inside the hooks themselves.
  use Cachex.Hook
  import Cachex.Spec

  @doc """
  Returns a hook definition for the default forward hook.
  """
  def create,
    do: create(:default_forward_hook)

  @doc """
  Returns a hook definition for a custom forward hook.
  """
  def create(module) when is_atom(module),
    do: hook(module: module, state: self())

  @doc """
  Binds a module for a given name and provided overrides.

  This is used to generate module definitions with a custom
  implementation and option set for the hook interfaces.
  """
  defmacro bind(pairs) do
    for { name, opts } <- pairs do
      # pull out all options, allowing their defaults
      async = Keyword.get(opts, :async, true)
      actions = Keyword.get(opts, :actions, :all)
      provisions = Keyword.get(opts, :provisions, [])
      timeout = Keyword.get(opts, :timeout, nil)
      type = Keyword.get(opts, :type, :post)

      quote do
        # define the module by name
        defmodule unquote(name) do
          use Cachex.Hook

          # apply configuration overrides
          def async?,
            do: unquote(async)
          def actions,
            do: unquote(actions)
          def provisions,
            do: unquote(provisions)
          def timeout,
            do: unquote(timeout)
          def type,
            do: unquote(type)

          @doc """
          Forwards received messages to the state process.
          """
          def handle_notify(msg, results, proc) do
            handle_info({ msg, results }, proc)
            { :ok, proc }
          end

          @doc """
          Forwards received messages to the state process.
          """
          def handle_provision(provision, proc) do
            handle_info(provision, proc)
            { :ok, proc }
          end

          @doc """
          Forwards received messages to the state process.
          """
          def handle_info(msg, proc) do
            send(proc, msg)
            { :noreply, proc }
          end
        end
      end
    end
  end
end
