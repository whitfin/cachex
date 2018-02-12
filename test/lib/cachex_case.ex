defmodule CachexCase do
  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use ExUnit.Case, async: false

      alias CachexCase.ExecuteHook
      alias CachexCase.ForwardHook
      alias CachexCase.Helper
      alias Cachex.Services

      import Cachex.Spec
      import Cachex.Errors
      import ExUnit.CaptureLog

      require Helper
      require ExecuteHook
      require ForwardHook
    end
  end
end
