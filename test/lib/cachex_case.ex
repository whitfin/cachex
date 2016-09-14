defmodule CachexCase do

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use Cachex.Macros
      use ExUnit.Case, async: false

      alias CachexCase.ExecuteHook
      alias CachexCase.ForwardHook
      alias CachexCase.Helper

      import ExUnit.CaptureLog

      ExUnit.Case.register_attribute(__ENV__, :ctx)
    end
  end

end
