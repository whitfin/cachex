Application.ensure_all_started(:cachex)

ExUnit.start()

defmodule TestHelper do
  use PowerAssert

  def create_cache(args \\ []) when is_list(args) do
    table =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    table_name = args[:name] || table

    Cachex.start_link(table_name, args)

    ExUnit.Callbacks.on_exit("delete #{table_name}", fn ->
      Eternal.stop(Cachex.Util.atom_append(table_name, "_eternal"))
    end)

    table_name
  end

  def gen_random_string_of_length(num) when is_number(num) do
    letters =
      ?a..?z
      |> Enum.to_list

    1..num
    |> Enum.map(fn(_) -> Enum.random(letters) end)
    |> List.to_string
  end

  def poll(timeout, expected, generator, start_time \\ Cachex.Util.now()) do
    try do
      assert(generator.() == expected)
    rescue
      e ->
        unless start_time + timeout > Cachex.Util.now() do
          raise e
        end
        poll(timeout, expected, generator, start_time)
    end
  end

end
