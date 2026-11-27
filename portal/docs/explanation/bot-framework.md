# The bot framework

This page tells why the parts between outside services and bots have
their present shape. For the list of the parts, see
[the reference](../reference/bots-and-webhooks.md).

## Many services, one shape

Slapdash must work with GitHub, GitLab, Forgejo, Linear, Slack and other
services. Each service has its own settings, its own webhook signatures
and its own names for things. If the portal had one table or one page for
each service, each new service would need a migration and new pages.

For this reason, one `Connection` resource holds all kinds of connection.
Its `provider` key names a module. The module declares the fields that a
connection needs, and the form is made from these fields. Settings go into
a plain map. Secrets go into a map that the vault encrypts. A new service
needs a new module, not a new table.

A provider also implements a behaviour for each capability that it has.
GitHub hosts repositories and sends webhooks, so its module implements
both. A chat service can send webhooks but host no repositories, so its
module implements only one. Other code asks the registry whether a
provider has a capability.

## Bots return actions

A bot gets a provider-neutral event and returns a list of actions, such as
"put this comment on the pull request". The bot does not call GitHub.
Slapdash performs the actions through the provider of the repository.

This has three results:

- A bot works with each provider that can perform its actions.
- A bot is a pure function in most cases, so a test needs no fake service.
- Slapdash records each action on the run, so people can see what a bot
  did.

## Each step is safe to repeat

Services send a webhook again when they get no answer, and jobs run again
after a crash. Each step must have the same result when it runs two times:

- A delivery is stored once for each delivery id of a connection.
- A bot run is made once for each event id, and event ids come from the
  delivery id.
- The runner keeps one job for each run while the job waits or runs.
- A comment carries a hidden key, and the provider does not post a second
  comment with the same key. This also covers a retry after the comment
  was posted but before the run was recorded.

## Runners

The runner is the part that runs a bot somewhere. A deterministic bot is a
small Elixir module, so the built-in runner runs it inside the portal, as
an Oban job. A bot that needs a sandbox, for example a bot that runs an
agent on a copy of the repository, needs a remote runner. Such a runner
implements the same `Slapdash.Bots.Runner` behaviour and records its
result on the same run.

## Where the data lives

Tenant data lives in the schema of its tenant. Enrollments, runs and
deliveries follow this rule.

A webhook request names only a connection, so Slapdash must find the
connection and its repositories before it knows the tenant. For this
reason, connections and repositories live in the `public` schema with a
tenant id, as memberships do.

Tables in a tenant schema have no foreign keys to tables in the `public`
schema. A tenant migration that adds such a key must lock the public
table. Transactions that write to that table then block the migration, and
a parallel tenant creation can deadlock. Code checks these references
instead.
