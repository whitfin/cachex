defmodule Cachex.Test.Case do
  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use ExUnit.Case, async: false

      alias Cachex.Test.Hook.Execute, as: ExecuteHook
      alias Cachex.Test.Hook.Forward, as: ForwardHook
      alias Cachex.Test.Hook.Callers, as: CallersHook
      alias Cachex.Test.Utils, as: TestUtils
      alias Cachex.Services

      import Cachex.Spec
      import Cachex.Error
      import ExUnit.CaptureLog

      require ExecuteHook
      require ForwardHook
      require TestUtils
    end
  end
end
