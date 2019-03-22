defmodule CachexTest do
  use CachexCase
  import Integer

  # Ensures that we're able to start a cache and link it to the current process.
  # We verify the link by spawning a cache from inside another thread and making
  # sure that the cache dies once the spawned process does.
  test "cache start with a link" do
    # fetch some names
    name1 = Helper.create_name()
    name2 = Helper.create_name()

    # cleanup on exit
    Helper.delete_on_exit(name1)
    Helper.delete_on_exit(name2)

    # this process should live
    { :ok, pid1 } = Cachex.start_link(name1)

    # check valid pid
    assert(is_pid(pid1))
    assert(Process.alive?(pid1))

    # this process should die
    spawn(fn ->
      { :ok, pid } = Cachex.start_link(name2)
      assert(is_pid(pid))
    end)

    # wait for spawn to end
    :timer.sleep(15)

    # process should've died
    assert(Process.whereis(name2) == nil)
  end

  # Ensures that we're able to start a cache without a link to the current process.
  # This is similar to the previous test, except a cache started in a spawned
  # process should stay alive after the process terminates.
  test "cache start without a link" do
    # fetch some names
    name1 = Helper.create_name()
    name2 = Helper.create_name()

    # cleanup on exit
    Helper.delete_on_exit(name1)
    Helper.delete_on_exit(name2)

    # this process should live
    { :ok, pid1 } = Cachex.start(name1)

    # check valid pid
    assert(is_pid(pid1))
    assert(Process.alive?(pid1))

    # this process should die
    spawn(fn ->
      { :ok, pid } = Cachex.start(name2)
      assert(is_pid(pid))
    end)

    # wait for spawn to end
    :timer.sleep(5)

    # process should've lived
    refute(Process.whereis(name2) == nil)
  end

  # Ensures that trying to start a cache when the application has not been started
  # causes an error to be returned. The application must be started because of our
  # global ETS table which stores cache states in the background.
  test "cache start when application not started" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # ensure that we start the app on exit
    on_exit(fn -> Application.ensure_all_started(:cachex) end)

    # capture the log to avoid bloating test output
    ExUnit.CaptureLog.capture_log(fn ->
      # here we kill the application
      Application.stop(:cachex)
    end)

    # try to start the cache with our cache name
    { :error, reason } = Cachex.start_link(name)

    # we should receive a prompt to start our application properly
    assert(reason == :not_started)
  end

  # This test does a simple check that a cache must be started with a valid atom
  # cache name, otherwise an error is raised (an ArgumentError). The error should
  # be a shorthand atom which can be used to debug what the issue was.
  test "cache start with invalid cache name" do
    # try to start the cache with an invalid name
    { :error, reason } = Cachex.start_link("fake_name")

    # we should've received an atom warning
    assert(reason == :invalid_name)
  end

  # This test ensures that we handle option parsing errors gracefully. If anything
  # goes wrong when parsing options, we exit early before starting the cache to
  # avoid bloating the Supervision tree.
  test "cache start with invalid options" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # try to start a cache with invalid hook definitions
    { :error, reason } = Cachex.start_link(name, [ hooks: hook(module: Missing) ])

    # we should've received an atom warning
    assert(reason == :invalid_hook)
  end

  # Naturally starting a cache when a cache already exists with the same name will
  # cause an issue, so this test is just ensuring that we handle it gracefully
  # by returning a small atom error saying that the cache name already exists.
  test "cache start with existing cache name" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # this cache should start successfully
    { :ok, pid } = Cachex.start_link(name)

    # check valid pid
    assert(is_pid(pid))
    assert(Process.alive?(pid))

    # try to start a cache with the same name
    { :error, reason1 } = Cachex.start_link(name)
    { :error, reason2 } = Cachex.start(name)

    # match the reason to be more granular
    assert(reason1 == { :already_started, pid })
    assert(reason2 == { :already_started, pid })
  end

  # We also need to make sure that a cache function executed against an invalid
  # cache name does not execute properly and returns an atom error which can be
  # used to debug further, rather than a generic error. We make sure to check
  # both execution with valid and invalid names to make sure we catch both.
  test "cache execution with an invalid name" do
    # fetch a name
    name = Helper.create_name()

    # try to execute a cache action against a missing cache and an invalid name
    { :error, reason1 } = Cachex.execute(name, &(&1))
    { :error, reason2 } = Cachex.execute("na", &(&1))

    # match the reason to be more granular
    assert(reason1 == :no_cache)
    assert(reason2 == :no_cache)
  end

  # This tests ensures that we provide delegate functions for Cachex functions
  # which unwrap errors automatically. We do this by creating a definition for
  # the @unsafe attribute which will bind the function at compile time.
  test "generating unsafe function delegates" do
    # grab all exported definitions
    definitions =
      :functions
      |> Cachex.__info__
      |> Keyword.drop([ :child_spec, :init, :start, :start_link ])

    # it has to always be even (one signature creates ! versions)
    assert(is_even(length(definitions)))

    # verify the size to cause errors on addition/removal
    assert(length(definitions) == 150)

    # validate all definitions
    for { name, arity } <- definitions, name != :execute do
      # create name as string
      name_st = "#{name}"

      # generate the new definition
      inverse =
        if String.ends_with?(name_st, "!") do
          :"#{String.replace_trailing(name_st, "!", "")}"
        else
          :"#{name_st}!"
        end

      # ensure the definitions contains the inverse
      assert({ inverse, arity } in definitions)
    end

    # create a basic test cache
    cache = Helper.create_cache()

    # validate an unsafe call to test handling
    assert_raise(Cachex.ExecutionError, fn ->
      Cachex.get!(:missing_cache, "key")
    end)

    # validate an unsafe call to test handling
    assert_raise(Cachex.ExecutionError, fn ->
      Cachex.transaction!(cache, [ "key" ], fn(_key) ->
        raise RuntimeError, message: "Ding dong! The witch is dead!"
      end)
    end)
  end
end
