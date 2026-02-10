defmodule Cachex.ErrorTest do
  use Cachex.Test.Case

  # This test ensures the integrity of all Error functions and forms. We iterate
  # all errors and check that the long form of the error is as expected.
  test "error generation and mapping" do
    # define all recognised errors
    errors = [
      cross_slot: "Target keys do not live on the same node",
      eisdir: "A directory path was provided when a file was expected",
      enoent: "Unable to access provided file path",
      invalid_command: "Invalid command definition provided",
      invalid_expiration: "Invalid expiration definition provided",
      invalid_hook: "Invalid hook definition provided",
      invalid_limit: "Invalid limit fields provided",
      invalid_match: "Invalid match specification provided",
      invalid_name: "Invalid cache name provided",
      invalid_option: "Invalid option syntax provided",
      invalid_pairs: "Invalid insertion pairs provided",
      invalid_router: "Invalid router definition provided",
      invalid_warmer: "Invalid warmer definition provided",
      janitor_disabled: "Specified janitor process running",
      no_cache: "Specified cache not running",
      non_numeric_value: "Attempted arithmetic operations on a non-numeric value",
      non_distributed: "Attempted to use a local function across nodes",
      not_started: "Cache table not active, have you started the Cachex application?",
      stats_disabled: "Stats are not enabled for the specified cache"
    ]

    # validate all error pairs
    for {err, msg} <- errors do
      assert Cachex.Error.explain(err) == msg
    end

    # make sure we're not missing any error definitions
    assert length(Cachex.Error.known()) == length(errors)
  end

  # This just ensures that unrecognised errors are simply
  # echoed back without change, in case of unknown errors.
  test "unknown error echoing" do
    assert Cachex.Error.explain(:nodedown) == :nodedown
  end

  # This test just validates the default error message against an Error.
  # There is nothing more to validate beyond the returned message.
  test "raising a default error" do
    raise Cachex.Error
  rescue
    e ->
      # capture the error message, ensure the message is valid
      assert Exception.message(e) == "Error during cache action"
  end
end
