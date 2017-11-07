defmodule Cachex.Constants do
  @moduledoc false
  # This module contains compile time constants so that they don't have to be
  # defined in multiple places, but don't also have to be built up repeatedly.

  @doc false
  defmacro __using__(_) do
    quote do
      use Cachex.Errors

      @notify_false          [ notify: false ]
      @purge_override_call   { :purge, [[]] }
      @purge_override_result { :ok, 1 }
      @purge_override        [ via: @purge_override_call, hook_result: @purge_override_result ]
    end
  end
end
