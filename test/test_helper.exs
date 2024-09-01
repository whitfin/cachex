# ensure that Cachex has been started
Application.ensure_all_started(:cachex)

# require test lib files
"#{Path.dirname(__ENV__.file)}/**/*.ex"
|> Path.wildcard()
|> Enum.reverse()
|> Enum.filter(&(!File.dir?(&1)))
|> Enum.each(&Code.require_file/1)

# start ExUnit with skips
ExUnit.start(exclude: [:skip])
