defmodule Cachex.ErrorsTest do
  use CachexCase

  # This test ensures the integrity of all Error functions and forms. We iterate
  # all errors and check that the long form of the error is as expected.
  test "error generation and mapping" do
    # define all recognised errors
    errors = [
      cross_slot:         "Target keys do not live on the same node",
      invalid_command:    "Invalid command definition provided",
      invalid_expiration: "Invalid expiration definition provided",
      invalid_fallback:   "Invalid fallback function provided",
      invalid_hook:       "Invalid hook definition provided",
      invalid_limit:      "Invalid limit fields provided",
      invalid_match:      "Invalid match specification provided",
      invalid_name:       "Invalid cache name provided",
      invalid_nodes:      "Invalid nodes list provided",
      invalid_option:     "Invalid option syntax provided",
      invalid_pairs:      "Invalid insertion pairs provided",
      invalid_warmer:     "Invalid warmer definition provided",
      janitor_disabled:   "Specified janitor process running",
      no_cache:           "Specified cache not running",
      non_numeric_value:  "Attempted arithmetic operations on a non-numeric value",
      non_distributed:    "Attempted to use a local function across nodes",
      not_started:        "Cache table not active, have you started the Cachex application?",
      stats_disabled:     "Stats are not enabled for the specified cache",
      unreachable_file:   "Unable to access provided file path"
    ]

    # validate all error pairs
    for { err, msg } <- errors do
      # retrieve the long form
      long_form = Cachex.Errors.long_form(err)

      # verify the message returned
      assert(long_form == msg)
    end

    # make sure we're not missing any error definitions
    assert(length(Cachex.Errors.known()) == length(errors))
  end

  # This just ensures that unrecognised errors are simply
  # echoed back without change, in case of unknown errors.
  test "unknown error echoing" do
    assert(Cachex.Errors.long_form(:nodedown) == :nodedown)
  end
end
