# Slapdash

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

Slapdash keeps environment variables to what it needs before it can reach
its database. Everything else lives in the database as Ash resources and is
set up by root in the admin pages at `/admin`:

- **Settings**: the public URL people reach Slapdash at, and the sender of
  outgoing mail.
- **Mail**: an SMTP server, Postmark, Mailgun or SendGrid. Until one is set
  up, Slapdash cannot email sign-in links (development falls back to the
  mailbox preview at <http://localhost:4000/dev/mailbox>).
- **GitHub sign-in**: a GitHub OAuth app. Until one is set up, the sign-in
  page does not offer GitHub.
- **Tenants**: see [Tenants and roles](#tenants-and-roles).

Passwords, API keys and client secrets are encrypted at rest with the
master key (`Slapdash.Vault`, AES-256-GCM), and the admin pages never show
them again after they are saved. Leaving a secret field blank keeps the
stored value.

On first boot in production, Slapdash generates its own `secret_key_base`
and token signing secret and stores them, encrypted, in the database.

### Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | Yes | PostgreSQL connection URL, `ecto://USER:PASS@HOST/DATABASE` |
| `SLAPDASH_MASTER_KEY` | Yes | Encrypts every secret Slapdash stores. 32 random bytes, Base64: `openssl rand -base64 32` |
| `PORT` | No | HTTP port. Defaults to `4000` |
| `POOL_SIZE` | No | Database connections. Defaults to `10` |
| `ECTO_IPV6` | No | `true` to reach the database over IPv6 |
| `PHX_SERVER` | For releases | Set by `bin/server` to start the web server |

Back up the master key apart from the database. Without it, nothing
encrypted in the database can be read, including the generated secrets.

Development and test need none of these; `config/dev.exs` and
`config/test.exs` hold local values.

## Connections, repositories and bots

Tenant administrators set up the rest in the tenant pages:

- **Connections** (`/tenants/:slug/connections`): links to outside
  services. The first kind is a GitHub App. Each connection that takes
  webhooks has its own URL, `/webhooks/<connection id>`.
- **Repositories** (`/tenants/:slug/repositories`): the repositories that
  the tenant's bots work on, and the bots on each repository.
- **Bot runs** (`/tenants/:slug/runs`): what each bot did, and why a run
  failed.

Bots run inside the portal as Oban jobs. Documentation:

- How-to: [Connect a GitHub App and turn on the Greeter bot](docs/how-to/connect-a-github-app.md)
- Reference: [Bots and webhooks](docs/reference/bots-and-webhooks.md)
- Explanation: [The bot framework](docs/explanation/bot-framework.md)

## Onboarding root

A fresh install has no users and no mail provider, so the first sign-in
link is printed rather than emailed. Run this against the release, with the
same environment as the server:

```sh
bin/slapdash eval 'Slapdash.Release.create_root("you@example.com", public_url: "https://slapdash.example.com")'
```

It makes that address root (creating the user if needed), saves the public
URL, and prints a single-use link that is valid for 10 minutes. Open it to
sign in, then set up mail, GitHub sign-in and tenants in the admin pages.
`public_url` is only needed the first time.

If you are ever locked out, print a fresh link for any existing user:

```sh
bin/slapdash eval 'Slapdash.Release.sign_in_link("you@example.com")'
```

`eval` starts only the database connection and the vault, so it works
whether or not the server is running. The NixOS module and the container
also run Erlang distribution on loopback, so `bin/slapdash rpc` and
`bin/slapdash remote` reach a running server (on NixOS, use the
`slapdash-eval`, `slapdash-rpc` and `slapdash-remote` commands the module
installs). In
development, call the same functions from `iex -S mix phx.server`.

## Signing in

Sign-in is by invitation only. There is no sign-up: an account exists only
after root creates it from the console, or after root or a tenant
administrator adds the person to a tenant. Invited people sign in with a
magic link sent by email, or with GitHub once root has set it up. The pages
are at `/sign-in`. A sign-in link request for an email without an account
sends nothing, and the page does not show whether the email has an account.

For GitHub sign-in, create an OAuth app in GitHub under Settings, Developer
settings, OAuth Apps, with the authorization callback URL that the admin
page shows (the public URL followed by `/auth/user/github/callback`). Enter
its client ID and secret on the GitHub sign-in admin page. Use one OAuth app
per environment.

The first GitHub sign-in links the GitHub account to the invited account
with the same email. GitHub must show that email as the verified primary
email. After that, the GitHub account signs in to the same account, also if
its email changes. Slapdash does not keep GitHub's OAuth access token.

## Tenants and roles

One Slapdash install can hold several tenants. Each tenant gets its own
PostgreSQL schema, `tenant_<slug>`, created with the tenant, so tenant data
is separated at the database level. The tenant list and memberships live in
the `public` schema.

There are three roles:

- **Root** is install-wide. Root manages settings, mail, GitHub sign-in and
  tenants, and can do everything in every tenant. Root is granted only from
  the console (`Slapdash.Release.create_root/2`).
- **Administrator** is per tenant: everything inside that tenant, including
  its members.
- **Engineer** is per tenant: works in the tenant and sees its members.

Members are managed at `/tenants/<slug>/members`. Adding someone by email is
how they are invited: it creates their account if needed, and they can then
sign in with that address.

## Self-hosting

The repository's `flake.nix` builds the server as a Mix release, configured
by the [environment variables](#environment-variables) above. The release's
`bin/migrate` runs pending migrations (the `public` schema, then each tenant
schema) and `bin/server` starts the server. Requests for any host other than
`localhost` are redirected to HTTPS, so run it behind a reverse proxy that
terminates TLS and sets `X-Forwarded-Proto`.

### NixOS

```nix
{
  inputs.slapdash.url = "github:rellen/slapdash";

  outputs = { nixpkgs, slapdash, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        slapdash.nixosModules.default
        ({ pkgs, ... }: {
          services.postgresql.package = pkgs.postgresql_17;
          services.slapdash = {
            enable = true;
            # Outside the Nix store, for example from sops-nix or agenix.
            # Generate it once with `openssl rand -base64 32` and back it up.
            masterKeyFile = "/run/secrets/slapdash-master-key";
          };
        })
      ];
    };
  };
}
```

Then onboard root as the machine's root user. `slapdash-eval` runs
`bin/slapdash eval` as the service user with the service's environment:

```sh
slapdash-eval 'Slapdash.Release.create_root("you@example.com", public_url: "https://slapdash.example.com")'
```

`slapdash-rpc EXPR` runs an expression inside the running server, and
`slapdash-remote` opens an IEx shell on it. They connect over Erlang
distribution, which listens on 127.0.0.1 only, with a cookie the module
creates in `/var/lib/slapdash/cookie` on first start.

By default the module creates a local PostgreSQL database and role, connects
over the Unix socket, and runs migrations before each start. Set
`services.slapdash.database.createLocally = false` and provide a
`DATABASE_URL` through `database.url` or `environmentFile` to use another
server. The server listens on port 4000 on all interfaces; open it with
`openFirewall` only if no reverse proxy sits on the same machine.

The module's earlier `host`, `secretKeyBaseFile`, `tokenSigningSecretFile`,
`github.*` and `mailFrom` options are gone: those settings now live in the
database.

### Container

```sh
nix build .#container
docker load < result
docker run --name slapdash -p 4000:4000 \
  -e DATABASE_URL=ecto://user:pass@db.example.com/slapdash \
  -e SLAPDASH_MASTER_KEY=... \
  slapdash:0.1.0
docker exec slapdash slapdash eval 'Slapdash.Release.create_root("you@example.com", public_url: "https://slapdash.example.com")'
```

The entrypoint runs migrations, then starts the server. `docker exec slapdash
slapdash rpc EXPR` and `docker exec -it slapdash slapdash remote` reach
the running server over Erlang distribution on the container's loopback. The database role
needs to be able to create the `citext` extension, which the database owner
can do, and to create schemas, one per tenant.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
