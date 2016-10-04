defmodule Cachex.FallbackTest do
  use CachexCase

  # This test verifies the ability to parse a Keyword List into a Cachex Fallback.
  # This is used inside `Cachex.Options` when parsing the fallback options just
  # to add a little more structure rather than a Keyword List being stored. We
  # just verify various option combinations in this test to cover most cases.
  test "parsing values into a Fallback" do
    # define our falbacks as options
    fallback1 = []
    fallback2 = [ action: &String.reverse/1 ]
    fallback3 = [ action: &String.reverse/1, state: {} ]
    fallback4 = [ state: {} ]
    fallback5 = { }

    # convert all options to fallbacks
    result1 = Cachex.Fallback.parse(fallback1)
    result2 = Cachex.Fallback.parse(fallback2)
    result3 = Cachex.Fallback.parse(fallback3)
    result4 = Cachex.Fallback.parse(fallback4)
    result5 = Cachex.Fallback.parse(fallback5)

    # the first and fifth should use defaults
    assert(result1 == %Cachex.Fallback{ })
    assert(result5 == %Cachex.Fallback{ })

    # the second should have an action but no state
    assert(result2 == %Cachex.Fallback{ action: &String.reverse/1 })

    # the third should have both an action and state
    assert(result3 == %Cachex.Fallback{
      action: &String.reverse/1,
      state: {}
    })

    # the fourth should have a state but no action
    assert(result4 == %Cachex.Fallback{ state: { } })
  end

end
