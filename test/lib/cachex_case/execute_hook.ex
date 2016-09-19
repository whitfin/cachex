defmodule CachexCase.ExecuteHook do
  @moduledoc false
  # This module provides a Cachex hook interface which simply forwards all messages
  # to the calling process. This is useful to validate that messages sent actually
  # do arrive as intended, without having to trust assertions inside the hooks
  # themselves.

  # implement behaviour
  use Cachex.Hook

  @doc false
  # This provides a simple creation interface for a forwarding hook, by defining
  # default options and allowing the caller to override as needed (or not at all).
  def create(opts \\ %{ }) do
    %Cachex.Hook{ struct(Cachex.Hook, opts) | args: self(), module: __MODULE__ }
  end

  @doc false
  # Forwards the received message on to the test process, and simply returns the
  # state as it was to start with.
  def handle_notify(fun, _results, proc) do
    handle_info(fun.(), proc)
    { :ok, proc }
  end

  @doc false
  # Forwards the received message on to the test process, and simply returns the
  # state as it was to start with.
  def handle_info(msg, proc) do
    send(proc, msg)
    { :noreply, proc }
  end

end
