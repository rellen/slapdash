defmodule Slapdash.MixProject do
  use Mix.Project

  # `mix git_ops.release` updates @version. Do not change it by hand.
  @version "0.1.0"

  def project do
    [
      app: :slapdash,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      usage_rules: usage_rules()
    ]
  end

  # Dependency usage rules synced into AGENTS.md by `mix usage_rules.sync`.
  # Everything between the `usage-rules-start`/`usage-rules-end` markers in
  # AGENTS.md is generated from this list; edit here, not there.
  #
  # Short top-level rules are inlined; the larger topic-specific sub-rules are
  # linked (into `deps/`) so AGENTS.md stays small enough to read in full.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: ["otp"]},
        "phoenix:elixir",
        "phoenix:phoenix",
        "phoenix:html",
        "phoenix:liveview",
        :shoddy,
        :shoddy_phoenix,
        {~r/^ash/, sub_rules: []},
        {~r/^ash/, sub_rules: :all, main: false, link: :markdown},
        {:igniter, link: :markdown}
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Slapdash.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:picosat_elixir, "~> 0.2"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_cloak, "~> 0.5"},
      {:cloak, "~> 1.1"},
      {:gen_smtp, "~> 1.3"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:usage_rules, "~> 1.3", only: [:dev]},
      {:git_ops, "~> 2.12", only: [:dev], runtime: false},
      {:phoenix, "~> 1.8.17"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      # Small helpers for Elixir and Phoenix code. Neither is on Hex, so mix.lock pins the
      # commit. shoddy_phoenix does not pull in shoddy, so both are listed.
      {:shoddy, github: "rellen/shoddy"},
      {:shoddy_phoenix, github: "rellen/shoddy_phoenix"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild slapdash", "esbuild slapdash_css"],
      "assets.deploy": [
        "esbuild slapdash --minify",
        "esbuild slapdash_css --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "ash.codegen --check",
        "test"
      ]
    ]
  end
end
