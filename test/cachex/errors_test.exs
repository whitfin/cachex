defmodule Cachex.ErrorsTest do
  use CachexCase

  # This test ensures the integrity of all Error functions and forms. We define
  # our pairs and assert that we have defined all of them by reading the exported
  # functions list from inside the Errors module. We then iterate all errors and
  # check that there is a function exposing the error (for compile time checking),
  # and that the long form of the error is as expected.
  test "error generation and mapping" do
    # define all recognised errors
    errors = [
      invalid_hook:      "Invalid hook definition provided",
      invalid_match:     "Invalid match specification provided",
      invalid_name:      "Invalid cache name provided",
      invalid_option:    "Invalid option syntax provided",
      janitor_disabled:  "Specified janitor process running",
      no_cache:          "Specified cache not running",
      non_numeric_value: "Attempted arithmetic operations on a non-numeric value",
      not_started:       "State table not active, have you started the Cachex application?",
      stats_disabled:    "Stats are not enabled for the specified cache"
    ]

    # retrieve the errors length
    length1 = length(errors)

    # fetch all public functions
    functions = Cachex.Errors.__info__(:functions)

    # sanitize the functions list
    sanitized = functions -- [
      long_form: 1
    ]

    # retrieve the sanitized length
    length2 = Enum.count(sanitized)

    # ensure the list is complete
    assert(length1 == length2)

    # define our validation
    validate = fn(err, msg) ->
      # call the error function
      error = apply(Cachex.Errors, err, [])

      # ensure the error comes back in a Tuple
      assert(error == { :error, err })

      # retrieve the long form
      long_form = Cachex.Errors.long_form(err)

      # verify the message returned
      assert(long_form == msg)
    end

    # validate all error pairs
    for { err, msg } <- errors do
      validate.(err, msg)
    end
  end

end
