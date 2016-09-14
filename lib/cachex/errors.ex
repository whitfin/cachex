defmodule Cachex.Errors do
  @moduledoc false

  @invalid_hook       { :error, :invalid_hook }
  @invalid_match      { :error, :invalid_match }
  @invalid_name       { :error, :invalid_name }
  @invalid_option     { :error, :invalid_option }
  @janitor_disabled   { :error, :janitor_disabled }
  @no_cache           { :error, :no_cache }
  @non_numeric_value  { :error, :non_numeric_value }
  @not_started        { :error, :not_started }
  @stats_disabled     { :error, :stats_disabled }

  @invalid_hook_def       "Invalid hook definition provided"
  @invalid_match_def      "Invalid match specification provided"
  @invalid_name_def       "Invalid cache name provided"
  @invalid_option_def     "Invalid option syntax provided"
  @janitor_disabled_def   "Specified janitor process running"
  @no_cache_def           "Specified cache not running"
  @non_numeric_value_def  "Attempted arithmetic operations on a non-numeric value"
  @not_started_def        "State table not active, have you started the Cachex application?"
  @stats_disabled_def     "Stats are not enabled for the specified cache"

  def invalid_hook do
    @invalid_hook
  end

  def invalid_match do
    @invalid_match
  end

  def invalid_name do
    @invalid_name
  end

  def invalid_option do
    @invalid_option
  end

  def janitor_disabled do
    @janitor_disabled
  end

  def no_cache do
    @no_cache
  end

  def non_numeric_value do
    @non_numeric_value
  end

  def not_started do
    @not_started
  end

  def stats_disabled do
    @stats_disabled
  end

  def long_form(:invalid_hook),
    do: @invalid_hook_def
  def long_form(:invalid_match),
    do: @invalid_match_def
  def long_form(:invalid_name),
    do: @invalid_name_def
  def long_form(:invalid_option),
    do: @invalid_option_def
  def long_form(:janitor_disabled),
    do: @janitor_disabled_def
  def long_form(:no_cache),
    do: @no_cache_def
  def long_form(:not_started),
    do: @not_started_def
  def long_form(:non_numeric_value),
    do: @non_numeric_value_def
  def long_form(:stats_disabled),
    do: @stats_disabled_def

end
