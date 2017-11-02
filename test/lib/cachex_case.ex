defmodule CachexCase do

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use ExUnit.Case, async: false

      alias CachexCase.ExecuteHook
      alias CachexCase.ForwardHook
      alias CachexCase.Helper

      import Cachex.Macros
      import ExUnit.CaptureLog
    end
  end

end
