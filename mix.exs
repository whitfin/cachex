defmodule Cachex.Mixfile do
  use Mix.Project

  @url_docs "http://hexdocs.pm/cachex"
  @url_github "https://github.com/whitfin/cachex"

  def project do
    [
      app: :cachex,
      name: "Cachex",
      description: "Powerful in-memory key/value storage for Elixir",
      package: %{
        files: [
          "lib",
          "mix.exs",
          "LICENSE"
        ],
        licenses: [ "MIT" ],
        links: %{
          "Docs" => @url_docs,
          "GitHub" => @url_github
        },
        maintainers: [ "Isaac Whitfield" ]
      },
      version: "2.1.0",
      elixir: "~> 1.2",
      deps: deps(),
      docs: [
        source_ref: "master",
        source_url: @url_github,
        main: "getting-started",
        extra_section: "guides",
        extras: [
          "docs/cache-warming/reactive-warming.md",
          "docs/cache-warming/proactive-warming.md",
          "docs/features/action-blocks.md",
          "docs/features/cache-limits.md",
          "docs/features/custom-commands.md",
          "docs/features/disk-interaction.md",
          "docs/features/execution-hooks.md",
          "docs/features/streaming-caches.md",
          "docs/features/ttl-implementation.md",
          "docs/migrations/migrating-to-v3.md",
          "docs/migrations/migrating-to-v2.md",
          "docs/getting-started.md"
        ],
        groups_for_extras: [
          "Features": Path.wildcard("docs/features/*.md"),
          "Cache Warming": Path.wildcard("docs/cache-warming/*.md"),
          "Migration": Path.wildcard("docs/migrations/*.md")
        ]
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        "docs": :docs,
        "cachex": :test,
        "coveralls": :test,
        "coveralls.html": :test,
        "coveralls.travis": :test
      ],
      aliases: [
        "bench": "run benchmarks/main.exs"
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger, :eternal],
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
      { :eternal, "~> 1.2" },
      { :unsafe,  "~> 1.0" },
      # Local dependencies
      { :benchee,     "~> 0.11", optional: true, only: [ :dev, :test ] },
      { :benchee_html, "~> 0.4", optional: true, only: [ :dev, :test ] },
      { :bmark,        "~> 1.0", optional: true, only: [ :dev, :test ] },
      { :credo,        "~> 0.8", optional: true, only: [ :dev, :test ] },
      { :excoveralls,  "~> 0.8", optional: true, only: [ :dev, :test ] },
      { :exprof,       "~> 0.2", optional: true, only: [ :dev, :test ] },
      # Documentation dependencies
      { :ex_doc, "~> 0.16", optional: true, only: [ :docs ] }
    ]
  end
end
