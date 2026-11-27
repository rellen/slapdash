defmodule Slapdash.Versions do
  @moduledoc """
  Version history for resources, with AshPaperTrail.

  A versioned resource adds `AshPaperTrail.Resource` to its extensions and
  this `paper_trail` block:

      paper_trail do
        mixin {Slapdash.Versions, :mixin, ["user_version"]}
        version_extensions authorizers: [Ash.Policy.Authorizer],
                           extensions: [Slapdash.Authz.Resource]
        belongs_to_actor :actor, Slapdash.Accounts.User,
          domain: Slapdash.Accounts,
          on_delete: :nilify
        store_action_name? true
        reference_source? false
        sensitive_attributes :ignore
        ignore_attributes [:inserted_at, :updated_at]
      end

  Its domain adds `AshPaperTrail.Domain` with `include_versions? true`.

  Each create, update and destroy then writes a row to `<table>_versions`
  with a snapshot of the record, the action name and the actor:

  - `belongs_to_actor` records the user who ran the action. Code that runs
    with `authorize?: false` for a user must still pass `actor:`, or the
    version has no actor.
  - `reference_source? false` keeps the versions when the record is
    destroyed.
  - `sensitive_attributes :ignore` keeps all sensitive attributes out of the
    versions. AshCloak makes its `encrypted_<name>` attributes sensitive, so
    no ciphertext goes into the versions. A resource that encrypts
    attributes also lists the `encrypted_<name>` attributes in
    `ignore_attributes`, to show the intent. Do not use `:redact`: it adds
    a `"REDACTED"` value for each sensitive attribute, also for the ignored
    attributes.
  - Version resources copy the multitenancy of their source. A resource that
    uses `multitenancy strategy :context` keeps its versions in the tenant's
    schema, and `mix ash.codegen` writes their migrations to
    `priv/repo/tenant_migrations/`.

  Only AshPaperTrail creates versions. The policies from `mixin/1` let
  `Slapdash.Authz` grants read them and forbid all other writes. The mixin
  also adds an AshPostgres index, so use it only on AshPostgres resources.
  The version resources have no tenant attribute, so only install-wide
  grants (root) reach versions of public-schema resources.
  """

  @doc """
  The body that AshPaperTrail adds to a version resource: its name for
  permission strings, an index on the source id, and its policies.
  """
  @spec mixin(String.t()) :: Macro.t()
  def mixin(resource_name) when is_binary(resource_name) do
    quote do
      authz do
        resource_name(unquote(resource_name))
      end

      postgres do
        custom_indexes do
          # A record's history is read by its id.
          index([:version_source_id])
        end
      end

      policies do
        bypass context_equals(:ash_paper_trail?, true) do
          authorize_if always()
        end

        policy action_type(:read) do
          authorize_if Slapdash.Authz.FilterCheck
        end
      end
    end
  end
end
