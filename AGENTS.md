# Slapdash

Slapdash is a self-hosted system that runs software bots on code
repositories and the applications that run from them. It has three parts:

1. The portal: the developer portal and control plane. It holds users,
   roles, tenants, instance configuration and the admin UI.
2. ShoddyBot: the bot framework. Bots use agent SDKs (for example the
   Claude Agent SDK) and connect to services such as GitHub, Linear and
   Slack.
3. The runners: the framework that runs bots on infrastructure. An operator
   uses a built-in runner (for example Fly Sprites) or supplies a runner.

This repository is a monorepo: each top-level directory is a separate project
with its own toolchain, dependencies and agent instructions.

## Projects

| Directory | What it is | Stack | Instructions |
| --- | --- | --- | --- |
| [`portal/`](portal/) | The portal: control plane server and web UI | Elixir, Ash, Phoenix, PostgreSQL | [`portal/AGENTS.md`](portal/AGENTS.md) |

The bot framework (`shoddybot/`) and the runners (`runners/`) get their own
top-level directories when work on them starts.

## How to work in this repository

- Before changing a project, read its `AGENTS.md`. It has the commands,
  conventions and definition of done. Where it conflicts with this file, the
  project's file wins inside that project.
- Run build, test and generator commands from inside the project directory
  (for example `cd portal && mix test`). Nothing builds from the repository root.
- Keep each change inside one project where you can. If a change crosses
  projects (for example an API the server exposes and a client consumes),
  update both sides in the same change, and update the server's tests for the
  contract.
- Each project owns its own `.gitignore`, lockfile and formatter config. Keep
  build output and dependencies out of git, and do not add tooling at the root
  that only one project needs.
- A new project gets its own top-level directory and its own `AGENTS.md`, and
  a row in the table above.

## Languages and tooling

- Server code is Elixir. Server data lives in PostgreSQL and is accessed
  through Ash and AshPostgres.
- Client-side web code is TypeScript. Do not add plain JavaScript beyond what
  the generators produce.
- Repository scripts are Bash (`#!/usr/bin/env bash` with `set -euo pipefail`),
  not Python or Node.js.
- Do not add dependencies casually. Prefer what the project already uses, and
  say why in the commit message when you add one.

## Toolchain

| Tool | Version |
| --- | --- |
| Elixir | 1.20 |
| Erlang/OTP | 29 |
| PostgreSQL | 17 or later |

The root `flake.nix` pins these versions. With Nix (flakes enabled), run
`nix develop .#portal` from the repository root for a shell with the `portal/`
toolchain, or install the versions above with your system's package manager.

## Nix

`flake.nix` is the one piece of root tooling, because it serves every
project. Each project keeps its Nix expressions in its own `nix/` directory
(`portal/nix/`), and the flake wires them together:

| Output | What it is |
| --- | --- |
| `packages.<system>.slapdash` (`default`) | The `portal/` Mix release |
| `packages.<linux>.container` | OCI image of the release |
| `nixosModules.slapdash` (`default`) | `services.slapdash` |
| `devShells.<system>.portal` (`default`) | Toolchain for `portal/` |
| `checks.<system>.*` | Package and image builds, Nix formatting, and a NixOS VM test of the module |

- Run `nix flake check` after changing anything under `nix/`, `flake.nix`
  or `flake.lock`, and `nix fmt` to format Nix files.
- When `portal/mix.lock` changes, update the `hash` of `mixFodDeps` in
  `portal/nix/package.nix`: set it to `lib.fakeHash`, run
  `nix build .#slapdash`, and copy the hash Nix reports.
- A new project adds `<project>/nix/shell.nix` and a `devShells` entry.

## Writing

- Write all code comments, documentation, descriptions, commit messages and
  pull requests in ASD-STE100 Simplified Technical English. Use short
  sentences, the active voice and one meaning for each word.
- Do not use mannered prose: no idioms, figures of speech, filler or
  decorative words.
- Write rules as project rules. Do not name people or "the owner" as the
  source of a rule. Write "Operators set up their own connections", not
  "The maintainer wants operators to set up their own connections".
- Write commit messages in the Conventional Commits format. See
  [Commits](#commits).

## Commits

- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
  for the subject: `type(scope): subject`. Write the subject in ASD-STE100,
  in the imperative mood and in lowercase, with no full stop.
- Use one of these types:

  | Type | Use it for |
  |------|------------|
  | `feat` | A new feature |
  | `fix` | A bug fix |
  | `docs` | Documentation only |
  | `refactor` | A code change that does not add a feature or fix a bug |
  | `perf` | A change that makes the code faster or use less memory |
  | `test` | New or changed tests only |
  | `build` | The build, Nix files or dependencies |
  | `ci` | Continuous integration configuration |
  | `chore` | Other work that does not change the shipped code |
  | `revert` | A commit that reverts an earlier commit |

- Use the project directory as the scope when the change is confined to one
  project: `feat(portal): add repository resource`. Do not use a scope when
  the change is in more than one project or at the repository root.
- Keep the full first line to 72 characters or fewer.
- Mark a breaking change with `!` after the type or scope
  (`feat(portal)!: remove the legacy API`), and add a `BREAKING CHANGE:`
  footer that tells what users must change.
- In the body, explain why the change was made. The diff already shows what
  changed.
- Do not rewrite commits that are on `main` to change their messages.
- Never commit secrets, credentials or `.env` files. A deployment supplies a
  few bootstrap environment variables (see `portal/README.md`); everything else
  is configured in the app and stored encrypted in its database.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
