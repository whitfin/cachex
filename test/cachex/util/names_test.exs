defmodule Cachex.Util.NamesTest do
  use CachexCase

  # This test verifies that we can generate names for cache components in a
  # consistent way. We define a mapping of component to name and ensure that the
  # function inside the Cachex.Util.Names module generates the correct definition.
  test "naming components using a cache" do
    # create a test cache name
    name = Helper.create_name()

    # generate possible combinations
    components = [
      eternal:   "#{name}_eternal",
      janitor:   "#{name}_janitor",
      locksmith: "#{name}_locksmith",
      stats:     "#{name}_stats"
    ]

    # retrieve the errors length
    length1 = length(components)

    # fetch all public functions
    functions = Cachex.Util.Names.__info__(:functions)

    # retrieve the functions length
    length2 = Enum.count(functions)

    # ensure the list is complete
    assert(length1 == length2)

    # define our validation
    validate = fn(component, expected) ->
      # convert to an suffixed name
      result = apply(Cachex.Util.Names, component, [name])

      # ensure we have an atom
      assert(is_atom(result))

      # convert to the binary version
      binary = Kernel.to_string(result)

      # verify the binary version
      assert(binary == expected)
    end

    # validate all known suffixes
    for { component, expected } <- components do
      validate.(component, expected)
    end
  end
end
