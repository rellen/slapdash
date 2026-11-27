# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  infer_generic_action_reactors?: false,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :authz,
        :cloak,
        :token,
        :user_identity,
        :postgres,
        :paper_trail,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:resources, :paper_trail, :policies, :authorization, :domain, :execution]
    ]
  ]

config :slapdash,
  ecto_repos: [Slapdash.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Slapdash.Accounts, Slapdash.Instance, Slapdash.Tenancy, Slapdash.Connections],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true]

# Background jobs. Oban keeps its tables in the `public` schema. Job
# arguments hold ids only, never secrets (see "Security" in AGENTS.md).
config :slapdash, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  repo: Slapdash.Repo,
  queues: [webhooks: 10, bots: 10],
  plugins: [{Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60}]

# Configure the endpoint
config :slapdash, SlapdashWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SlapdashWeb.ErrorHTML, json: SlapdashWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Slapdash.PubSub,
  live_view: [signing_salt: "p66KWx+z"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Mail goes through the provider root configures in the admin pages (see
# Slapdash.Mailer). Development and test set a fallback adapter.
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure esbuild (the version is required). It bundles both app.js and
# app.css; there is no CSS framework or Node.js toolchain.
config :esbuild,
  version: "0.27.2",
  # Use an existing esbuild binary instead of downloading one when set, for
  # example by the Nix build and dev shell.
  path: System.get_env("MIX_ESBUILD_PATH"),
  slapdash: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  slapdash_css: [
    args:
      ~w(css/app.css --bundle --outdir=../priv/static/assets/css --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
