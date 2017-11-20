defmodule Cachex.Include do
  @moduledoc false
  # Header-style module to include to provide common utilities.

  @doc false
  defmacro __using__(options) do
    for { opt, true } <- options do
      define(opt)
    end
  end

  # Imports all action definitions
  defp define(:actions),
    do: quote(do: import Cachex.Actions)

  # Imports a set of constants
  defp define(:constants) do
    quote do
      use Cachex.Errors

      @notify_false          [ notify: false ]
      @purge_override_call   { :purge, [[]] }
      @purge_override_result { :ok, 1 }
      @purge_override        [ via: @purge_override_call, hook_result: @purge_override_result ]
    end
  end

  # Imports all models
  defp define(:models),
    do: quote(do: import Cachex.Models)
end
