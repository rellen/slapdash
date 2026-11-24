import Config

config :ramshackle, token_signing_secret: "WEpJIUZaLAphjb91818+d66ugNP4Rl9E"

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "9B6ZgMSaQ0gK6pW6EUpvvJyNqsAnfJSh89YHcga4JEQ",
  disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ramshackle, Ramshackle.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ramshackle_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ramshackle, RamshackleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CflAseZ0eO/7P0YDfs8mSE6IWlhPtiQRlajwgCajBxrUtGHlX+jMX0PqKmeV3p3E",
  server: false

# In test we don't send emails
config :ramshackle, Ramshackle.Mailer, adapter: Swoosh.Adapters.Test

config :ramshackle, boot_secrets: :config
config :ramshackle, Ramshackle.Vault, key: "aENpb8aZGlJKGgjCRjMHZQsb26UwWrez0r9oSnsVRdw="

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
