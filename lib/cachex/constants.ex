defmodule Cachex.Constants do
  @moduledoc false
  # This module contains compile time constants so that they don't have to be
  # defined in multiple places, but don't also have to be built up repeatedly.

  @doc false
  defmacro __using__(_) do
    quote do
      @notify_false             [ notify: false ]
      @purge_override_call      { :purge, [[]] }
      @purge_override_result    { :ok, 1 }
      @purge_override           [ via: @purge_override_call, hook_result: @purge_override_result ]

      @error_invalid_command    { :error, :invalid_command }
      @error_invalid_hook       { :error, :invalid_hook }
      @error_invalid_match      { :error, :invalid_match }
      @error_invalid_name       { :error, :invalid_name }
      @error_invalid_option     { :error, :invalid_option }
      @error_janitor_disabled   { :error, :janitor_disabled }
      @error_no_cache           { :error, :no_cache }
      @error_non_numeric_value  { :error, :non_numeric_value }
      @error_not_started        { :error, :not_started }
      @error_stats_disabled     { :error, :stats_disabled }
      @error_unreachable_file   { :error, :unreachable_file }
    end
  end

end
