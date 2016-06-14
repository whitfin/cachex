ExUnit.start()

defmodule TestHelper do

  def create_cache(args \\ []) when is_list(args) do
    table =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    Cachex.start_link(args ++ [name: table])

    table_name = args[:name] || table

    ExUnit.Callbacks.on_exit("delete #{table_name}", fn ->
      :mnesia.delete_table(table_name)
    end)

    table_name
  end

  def gen_random_string_of_length(num) when is_number(num) do
    :random.seed(:erlang.system_time)

    letters =
      ?a..?z
      |> Enum.to_list

    1..num
    |> Enum.map(fn(_) -> Enum.random(letters) end)
    |> List.to_string
  end

  def remote_call(node, func, args),
  do: :rpc.call(node, Cachex, func, args)

  def start_remote_cache(node, args),
  do: remote_call(node, :start, args)

end
