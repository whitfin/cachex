defmodule Cachex.Mixfile do
  use Mix.Project

  @url_docs "http://hexdocs.pm/cachex"
  @url_github "https://github.com/zackehh/cachex"

  def project do
    [
      app: :cachex,
      name: "Cachex",
      description: "Powerful in-memory key/value storage for Elixir",
      package: %{
        files: [
          "lib",
          "mix.exs",
          "LICENSE",
          "README.md"
        ],
        licenses: [ "MIT" ],
        links: %{
          "Docs" => @url_docs,
          "GitHub" => @url_github
        },
        maintainers: [ "Isaac Whitfield" ]
      },
      version: "1.2.0",
      elixir: "~> 1.2",
      deps: deps,
      docs: [
        extras: [ "README.md" ],
        source_ref: "master",
        source_url: @url_github
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        "cachex": :test
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger, :mnesia, :eternal],
      mod: {Cachex.Application, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      # Production dependencies
      { :eternal, "~> 1.0.3" },
      # Local dependencies
      { :benchfella,   "~> 0.3.2",  optional: true, only: [ :dev, :test ] },
      { :benchwarmer,  "~> 0.0.2",  optional: true, only: [ :dev, :test ] },
      { :credo,        "~> 0.4.3",  optional: true, only: [ :dev, :test ] },
      { :earmark,      "~> 0.2.1",  optional: true, only: [ :dev, :test ] },
      { :ex_doc,       "~> 0.12.0", optional: true, only: [ :dev, :test ] },
      { :excoveralls,  "~> 0.5.4",  optional: true, only: [ :dev, :test ] },
      { :exprof,       "~> 0.2.0",  optional: true, only: [ :dev, :test ] },
      { :power_assert, "~> 0.0.8",  optional: true, only: [ :dev, :test ] }
    ]
  end
end
