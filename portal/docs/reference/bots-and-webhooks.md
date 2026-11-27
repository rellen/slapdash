# Bots and webhooks reference

This page lists the parts of the portal that connect outside services to
bots. For the reasons behind them, see
[the explanation of the bot framework](../explanation/bot-framework.md).

## Pages

All pages are for members of the tenant. Only root and the administrators
of the tenant see the controls.

Each page is at `/<slug>/<page>` on the public URL. When root turns on
**Serve each tenant on its own subdomain** at `/admin`, each page is also
at `/<page>` on `<slug>.<public URL host>`. For example, `/acme/runs` and
`https://acme.slapdash.example.com/runs` are the same page.

| Path | Content |
| --- | --- |
| `/:slug/connections` | The connections of the tenant, and forms to add, change and remove them |
| `/:slug/repositories` | The repositories of the tenant, and the bots on each repository |
| `/:slug/runs` | The latest 50 bot runs, newest first |

## Webhook endpoint

`POST /webhooks/:connection_id`

The endpoint takes a JSON body. It does not use a session or a CSRF token.
The provider of the connection checks the signature of each request.

| Status | Meaning |
| --- | --- |
| `202` | Slapdash stored the delivery. A repeated delivery gets the same status. |
| `400` | The request does not have the headers of a delivery. |
| `401` | The signature is not correct. |
| `404` | No connection with this id takes webhooks. |

## Providers

Set the providers with `config :slapdash, :providers`.

| Key | Module | Behaviours |
| --- | --- | --- |
| `github_app` | `Slapdash.Providers.GitHub.App` | Provider, repository host, webhook source |

### `github_app` settings and secrets

| Field | Kind | Default |
| --- | --- | --- |
| `app_id` | Setting, required | |
| `web_url` | Setting | `https://github.com` |
| `api_url` | Setting | `https://api.github.com` |
| `private_key` | Secret, required | |
| `webhook_secret` | Secret, required | |

The webhook source checks `X-Hub-Signature-256`. It reads the delivery id
from `X-GitHub-Delivery` and the event from `X-GitHub-Event`.

## Behaviours

| Behaviour | A module that implements it |
| --- | --- |
| `Slapdash.Connections.Provider` | Declares the fields of a kind of connection and checks them |
| `Slapdash.Repositories.Host` | Checks repository paths, gives web URLs and puts comments |
| `Slapdash.Webhooks.Source` | Checks, reads and turns webhook deliveries into bot events |
| `Slapdash.Bots.Bot` | Turns an event into a list of actions |
| `Slapdash.Bots.Runner` | Runs a queued bot run somewhere |

## Bots

Set the bots with `config :slapdash, :bots`.

| Key | Module | Events | Actions |
| --- | --- | --- | --- |
| `greeter` | `Slapdash.Bots.Greeter` | `:pull_request_opened` | One comment with the key `greeter` |

## Event types

| Type | Meaning |
| --- | --- |
| `:pull_request_opened` | Somebody opened a pull request (GitHub, Forgejo) or a merge request (GitLab) |

## Statuses

| Record | Statuses |
| --- | --- |
| Delivery | `received`, `processed`, `ignored`, `failed` |
| Run | `queued`, `running`, `succeeded`, `failed` |

A delivery is `ignored` when it has no event for a repository of its
connection.

## Oban queues

| Queue | Jobs |
| --- | --- |
| `webhooks` | `Slapdash.Webhooks.ProcessDelivery`: turns one delivery into events |
| `bots` | `Slapdash.Bots.Runners.InProcess`: runs one bot run, with up to 5 attempts |

## Where the data is

| Data | Schema |
| --- | --- |
| Connections, repositories | `public`, with a tenant id |
| Enrollments, runs, deliveries | The schema of the tenant |
