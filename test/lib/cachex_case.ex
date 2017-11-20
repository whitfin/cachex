defmodule CachexCase do
  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use ExUnit.Case, async: false
      use Cachex.Include, models: true

      alias CachexCase.ExecuteHook
      alias CachexCase.ForwardHook
      alias CachexCase.Helper
      alias Cachex.Services

      import ExUnit.CaptureLog
    end
  end
end
