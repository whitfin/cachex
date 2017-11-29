defmodule CachexCase.Helper do
  @moduledoc false
  # This module contains various helper functions for tests, such as shorthanding
  # the ability to create caches, polling for messages, and polling for conditions.
  # Generally it just makes writing tests a lot easier and more convenient.

  # import assertion stuff
  import Cachex.Spec
  import ExUnit.Assertions

  # a list of letters A - Z
  @alphabet Enum.to_list(?a..?z)

  @doc false
  # Creates a cache using the given arguments to construct the cache options. We
  # return the name in case we're using the defaults, so that callers can generate
  # a random cache with a random name. We make sure to trigger a delete to happen
  # on test exit in order to avoid bloating ETS and memory unnecessarily.
  def create_cache(name \\ [], args \\ []) do
    { name, args } = cond do
      is_atom(name) and is_list(args) ->
        { name, args }
      is_list(name) ->
        { create_name(), name }
    end

    { :ok, _pid } = Cachex.start_link(name, args)

    delete_on_exit(name)
  end

  @doc false
  # Creates a cache name. These names are atoms of 8 random characters between
  # the letters A - Z. This is used to generate random cache names for tests.
  def create_name do
    8
    |> gen_rand_bytes
    |> String.to_atom
  end

  @doc false
  # Triggers a cache to be deleted at the end of the test. We have to pass this
  # through to the TestHelper module as we don't have a valid ExUnit context to
  # be able to define the execution hook correctly.
  def delete_on_exit(name),
    do: TestHelper.delete_on_exit(name) && name

  @doc false
  # Flush all messages in the process queue. If there is no message in the mailbox,
  # then we immediately return nil.
  def flush do
    receive do
      _ -> flush()
    after
      0 -> nil
    end
  end

  @doc false
  # Generates a number of random bytes to be returned as a binary, for use when
  # creating random messages and cache names.
  def gen_rand_bytes(num) when is_number(num) do
    1..num
    |> Enum.map(fn(_) -> Enum.random(@alphabet) end)
    |> List.to_string
  end

  @doc false
  # Provides the ability to poll for a condition to become true. Truthiness is
  # calculated using assertions. If the condition fails, we try again over and
  # over until a threshold is hit. Once the threshold is hit, we raise the last
  # known assertion error, as it's unlikely the test will pass going forward.
  def poll(timeout, expected, generator, start_time \\ now()) do
    try do
      assert(generator.() == expected)
    rescue
      e ->
        unless start_time + timeout > now() do
          raise e
        end
        poll(timeout, expected, generator, start_time)
    end
  end

end
