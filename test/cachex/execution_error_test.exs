defmodule Cachex.ExecutionErrorTest do
  use CachexCase

  # This test just validates the default error message against an ExecutionError.
  # There is nothing more to validate beyond the returned message.
  test "raising a default ExecutionError" do
    raise Cachex.ExecutionError
  rescue
    e ->
      # capture the error message
      msg = Exception.message(e)

      # ensure the message is valid
      assert(msg == "Error during action execution")
  end
end
