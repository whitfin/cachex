ExUnit.start()

defmodule TestHelper do

  def create_cache(args \\ []) when is_list(args) do
    table =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    Cachex.start_link(args ++ [name: table])

    table
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

  def read_files_r(root) do
    root
    |> File.ls!
    |> Enum.map(&(Path.join(root, &1)))
    |> Enum.reduce([], fn(path, paths) ->
        if File.dir?(path) do
          [read_files_r(path)|paths]
        else
          [path|paths]
        end
       end)
    |> Enum.to_list
    |> List.flatten
    |> Enum.reverse
  end

end

root =
  __ENV__.file
  |> Path.dirname
  |> Path.join("cachex_test")

root
|> TestHelper.read_files_r
|> Enum.each(&(Code.require_file/1))
