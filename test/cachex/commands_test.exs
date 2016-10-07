defmodule Cachex.CommandsTest do
  use CachexCase

  # This test ensures that we can successfully parse a list of commands into a
  # Map of commands, ensuring that all commands are valid before doing so. To
  # check this, we try parse both valid and invalid lists of commands to ensure
  # that we receive a working Map for the valid lists and an error otherwise.
  test "parsing a list of commands" do
    # define some functions
    fun1 = fn(_) -> [ 1, 2, 3 ] end

    # define valid command lists
    v_cmds1 = [ ]
    v_cmds2 = [ lpop: { :return, fun1 } ]

    # define invalid command lists
    i_cmds1 = [ 1 ]
    i_cmds2 = [ lpop: 1 ]

    # attempt to validate
    results1 = Cachex.Commands.parse(v_cmds1)
    results2 = Cachex.Commands.parse(v_cmds2)

    # the first two should be parsed into maps
    assert(results1 == { :ok, %{ } })
    assert(results2 == { :ok, %{ lpop: { :return, fun1 } } })

    # parse the rest
    results3 = Cachex.Commands.parse(i_cmds1)
    results4 = Cachex.Commands.parse(i_cmds2)

    # the remaining five are invalid
    assert(results3 == { :error, :invalid_command })
    assert(results4 == { :error, :invalid_command })
  end

  # This test ensures that we can successfully validate a list of commands. To
  # check this, we validate both valid and invalid lists of commands to ensure
  # that we receive an `:ok` value on success, and an error on failure.
  test "validating a list of commands" do
    # define valid command lists
    v_cmds1 = [ ]
    v_cmds2 = [ lpop: { :return, &(&1) } ]

    # define invalid command lists
    i_cmds1 = [ 1 ]
    i_cmds2 = [ lpop: 1 ]
    i_cmds3 = [ lpop: { :tag, &(&1) } ]
    i_cmds4 = [ lpop: { :return, &({ &1, &2 }) } ]
    i_cmds5 = nil

    # attempt to validate all
    results1 = Cachex.Commands.validate(v_cmds1)
    results2 = Cachex.Commands.validate(v_cmds2)

    # the first two should be ok
    assert(results1 == :ok)
    assert(results2 == :ok)

    # validate the rest
    results3 = Cachex.Commands.validate(i_cmds1)
    results4 = Cachex.Commands.validate(i_cmds2)
    results5 = Cachex.Commands.validate(i_cmds3)
    results6 = Cachex.Commands.validate(i_cmds4)
    results7 = Cachex.Commands.validate(i_cmds5)

    # the remaining five are invalid
    assert(results3 == { :error, :invalid_command })
    assert(results4 == { :error, :invalid_command })
    assert(results5 == { :error, :invalid_command })
    assert(results6 == { :error, :invalid_command })
    assert(results7 == { :error, :invalid_command })
  end

end
