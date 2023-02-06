defmodule Cachex.Mixfile do
  use Mix.Project

  @version "3.6.0"
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
        licenses: ["MIT"],
        links: %{
          "Docs" => @url_docs,
          "GitHub" => @url_github
        },
        maintainers: ["Isaac Whitfield"]
      },
      version: @version,
      elixir: "~> 1.5",
      deps: deps(),
      docs: [
        source_ref: "v#{@version}",
        source_url: @url_github,
        main: "getting-started",
        extra_section: "guides",
        extras: [
          "docs/features/cache-warming/reactive-warming.md",
          "docs/features/cache-warming/proactive-warming.md",
          "docs/features/action-blocks.md",
          "docs/features/cache-limits.md",
          "docs/features/custom-commands.md",
          "docs/features/disk-interaction.md",
          "docs/features/distributed-caches.md",
          "docs/features/execution-hooks.md",
          "docs/features/streaming-caches.md",
          "docs/features/ttl-implementation.md",
          "docs/migrations/migrating-to-v3.md",
          "docs/migrations/migrating-to-v2.md",
          "docs/getting-started.md"
        ],
        groups_for_extras: [
          Features: Path.wildcard("docs/features/*.md"),
          "Cache Warming": Path.wildcard("docs/features/cache-warming/*.md"),
          Migration: Path.wildcard("docs/migrations/*.md")
        ]
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        docs: :docs,
        bench: :bench,
        credo: :lint,
        cachex: :test,
        coveralls: :cover,
        "coveralls.html": :cover,
        "coveralls.travis": :cover
      ],
      aliases: [
        bench: "run benchmarks/main.exs"
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      mod: {Cachex.Application, []},
      extra_applications: [:unsafe]
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
      {:eternal, "~> 1.2"},
      {:jumper, "~> 1.0"},
      {:sleeplocks, "~> 1.1"},
      {:unsafe, "~> 1.0"},
      # Testing dependencies
      {:excoveralls, "~> 0.15", optional: true, only: [:cover]},
      {:local_cluster, "~> 1.1", optional: true, only: [:cover, :test]},
      # Linting dependencies
      {:credo, "~> 1.6", optional: true, only: [:lint]},
      # Benchmarking dependencies
      {:benchee, "~> 1.1", optional: true, only: [:bench]},
      {:benchee_html, "~> 1.0", optional: true, only: [:bench]},
      # Documentation dependencies
      {:ex_doc, "~> 0.29", optional: true, only: [:docs]}
    ]
  end
end
