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
      elixir: "~> 1.7",
      deps: deps(),
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: @url_github,
        extra_section: "guides",
        extras: [
          "docs/extensions/custom-commands.md",
          "docs/extensions/execution-lifecycle.md",
          "docs/general/action-blocks.md",
          "docs/general/disk-interaction.md",
          "docs/general/streaming-caches.md",
          "docs/management/limiting-caches.md",
          "docs/management/expiring-records.md",
          "docs/migrations/migrating-to-v3.md",
          "docs/migrations/migrating-to-v2.md",
          "docs/routing/distributed-caches.md",
          "docs/warming/reactive-warming.md",
          "docs/warming/proactive-warming.md",
          "README.md"
        ],
        groups_for_extras: [
          General: Path.wildcard("docs/general/*.md"),
          Management: Path.wildcard("docs/management/*.md"),
          Routing: Path.wildcard("docs/routing/*.md"),
          Warming: Path.wildcard("docs/warming/*.md"),
          Extensions: Path.wildcard("docs/extensions/*.md"),
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
        bench: "run benchmarks/main.exs",
        test: [&start_epmd/1, "test"]
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
      {:ex_hash_ring, "~> 6.0"},
      {:jumper, "~> 1.0"},
      {:sleeplocks, "~> 1.1"},
      {:unsafe, "~> 1.0"},
      # Testing dependencies
      {:excoveralls, "~> 0.15", optional: true, only: [:cover]},
      {:local_cluster, "~> 2.1", optional: true, only: [:cover, :test]},
      # Linting dependencies
      {:credo, "~> 1.7", optional: true, only: [:lint]},
      # Benchmarking dependencies
      {:benchee, "~> 1.1", optional: true, only: [:bench]},
      {:benchee_html, "~> 1.0", optional: true, only: [:bench]},
      # Documentation dependencies
      {:ex_doc, "~> 0.29", optional: true, only: [:docs]}
    ]
  end

  # Start epmd before test cases are run.
  defp start_epmd(_) do
    {_, 0} = System.cmd("epmd", ["-daemon"])
    :ok
  end
end
