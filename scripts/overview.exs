root =
  __ENV__.file
  |> Path.dirname()
  |> Path.dirname()

content =
  root
  |> Path.join("README.md")
  |> File.read!()
  |> String.split("\n## Benchmarks")
  |> List.first()
  |> String.split("\n", parts: 3)
  |> List.last()

root
|> Path.join("docs")
|> Path.join("overview.md")
|> File.write!("# Getting Started\n" <> content)
