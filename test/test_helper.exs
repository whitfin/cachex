# ensure that Cachex has been started
Application.ensure_all_started(:cachex)

# pattern to find test library files
"#{Path.dirname(__ENV__.file)}/**/*.ex"
# locate via Path
|> Path.wildcard()
# roughly sort by most nested
|> Enum.sort_by(&String.length/1)
# nested first
|> Enum.reverse()
# only attempt to import files
|> Enum.filter(&(!File.dir?(&1)))
# load each found module via Code
|> Enum.each(&Code.require_file/1)

# start ExUnit with skips
ExUnit.start(exclude: [:skip])
