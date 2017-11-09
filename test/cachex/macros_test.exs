defmodule Cachex.MacrosTest do
  use CachexCase

  # This test ensures that we can retrieve a three element Tuple from a function
  # head AST, regardless of whether the function head has guard clauses or not.
  test "retrieving a functions name and arguments" do
    # define a function head AST
    head1 = {
      :inspect,
      [ line: 1151 ],
      [
        { :cache,   [ line: 1151 ], nil },
        { :options, [ line: 1151 ], nil }
      ]
    }

    # define a function head AST with a when clause
    head2 = {
      :when,
      [ line: 1151 ],
      [
        {
          :inspect,
          [ line: 1151 ],
          [
            { :cache,   [ line: 1151 ], nil },
            { :options, [ line: 1151 ], nil }
          ]
        },
        { :is_list, [ line: 1151 ], [ { :options, [ line: 1151 ], nil } ] }
      ]
    }

    # define a function head AST with a multi when clause
    head3 = {
      :when,
      [ line: 1151 ],
      [
        {
          :inspect,
          [ line: 1151 ],
          [
            { :cache,   [ line: 1151 ], nil },
            { :options, [ line: 1151 ], nil }
          ]
        },
        {
          :and,
          [ line: 1151 ],
          [
            { :is_list, [ line: 1151 ], [ { :options, [ line: 1151 ], nil } ] },
            { :is_list, [ line: 1151 ], [ { :options, [ line: 1151 ], nil } ] }
          ]
        }
      ]
    }

    # retrieve the name and arguments for each head
    result1 = Cachex.Macros.unpack_head(head1)
    result2 = Cachex.Macros.unpack_head(head2)
    result3 = Cachex.Macros.unpack_head(head3)

    # grab subsections of the expected AST
    { _, _, expected_arguments } = head1
    { _, _, [ _, expected_conditions1 ] } = head2
    { _, _, [ _, expected_conditions2 ] } = head3

    # both should equal the base AST
    assert(result1 == { :inspect, expected_arguments, nil })
    assert(result2 == { :inspect, expected_arguments, expected_conditions1 })
    assert(result3 == { :inspect, expected_arguments, expected_conditions2 })
  end

  # This test ensures that we can correctly strip any default clauses from a set
  # of arguments AST. We make sure to process a combination of both required and
  # optional arguments to ensure that we can handle both, as well as multiple
  # optional arguments to make sure that they all are correctly replaced.
  test "stripping defaults from function AST" do
    # define a function args list with defaults
    args = [
      { :cache, [ line: 234 ], nil },
      { :key,   [ line: 234 ], nil },
      { :\\,    [ line: 234 ], [ { :options, [ line: 234 ], nil }, [ ] ]  },
      { :\\,    [ line: 234 ], [ { :bonuses, [ line: 234 ], nil }, [ ] ]  }
    ]

    # trim the defaults
    trimmed = Cachex.Macros.trim_defaults(args)

    # ensure the defaults have been removed
    assert(trimmed == [
      { :cache,   [ line: 234 ], nil },
      { :key,     [ line: 234 ], nil },
      { :options, [ line: 234 ], nil },
      { :bonuses, [ line: 234 ], nil }
    ])
  end
end
