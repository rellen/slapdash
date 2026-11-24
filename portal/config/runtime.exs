import Config

# config/runtime.exs runs for every environment, including releases, after
# compilation and before the system starts.
#
# Slapdash keeps environment variables to what it needs before it can reach
# its database. Everything else (the public URL, mail, GitHub sign-in,
# tenants) is configured by root in the admin pages and stored with Ash,
# secrets encrypted with the master key. secret_key_base and the token
# signing secret are generated on first boot (Slapdash.Instance.Boot).
#
# In production:
#
# | Variable              | Required | Purpose                                      |
# | --------------------- | -------- | -------------------------------------------- |
# | DATABASE_URL          | Yes      | ecto://USER:PASS@HOST/DATABASE               |
# | SLAPDASH_MASTER_KEY  | Yes      | Encrypts stored secrets. See Slapdash.Vault |
# | PORT                  | No       | HTTP port, default 4000                      |
# | POOL_SIZE             | No       | Database connections, default 10             |
# | ECTO_IPV6             | No       | `true` to reach the database over IPv6       |
# | PHX_SERVER            | Releases | Set by bin/server to start the HTTP server   |

if Shoddy.Env.boolean("PHX_SERVER", default: false) do
  config :slapdash, SlapdashWeb.Endpoint, server: true
end

config :slapdash, SlapdashWeb.Endpoint,
  http: [port: Shoddy.Env.integer("PORT", default: 4000, min: 1, max: 65_535)]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :slapdash, SlapdashWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/slapdash_web/router\.ex$"E,
        ~r"lib/slapdash_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  config :slapdash, Slapdash.Repo,
    # ssl: true,
    url: Shoddy.Env.string("DATABASE_URL"),
    pool_size: Shoddy.Env.integer("POOL_SIZE", default: 10, min: 1),
    socket_options:
      if(Shoddy.Env.boolean("ECTO_IPV6", default: false, digits: true), do: [:inet6], else: [])

  # Encrypts every secret Slapdash stores. 32 random bytes, Base64-encoded:
  # `openssl rand -base64 32`. Keep a copy apart from the database; without
  # it the stored secrets cannot be read. Slapdash.Vault checks the key when
  # it starts.
  config :slapdash, Slapdash.Vault, key: Shoddy.Env.string("SLAPDASH_MASTER_KEY")

  config :slapdash, SlapdashWeb.Endpoint,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # See https://bandit.hexdocs.pm/Bandit.html#t:options/0
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    # The public URL lives in the database, so origins are checked there.
    check_origin: {SlapdashWeb.Origin, :allowed?, []}
end
