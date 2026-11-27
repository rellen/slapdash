defmodule Slapdash.Instance.Settings do
  @moduledoc """
  Install-wide settings: the public URL Slapdash is reached at, and the
  sender used for outgoing mail. There is at most one row.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource, AshPaperTrail.Resource]

  authz do
    resource_name("instance_settings")
  end

  postgres do
    table "instance_settings"
    repo Slapdash.Repo

    check_constraints do
      check_constraint :id, "instance_settings_singleton", check: "id = 1"
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["instance_settings_version"]}

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

  actions do
    defaults [:read]

    read :current do
      get? true
      filter expr(id == 1)
    end

    create :configure do
      accept [:public_url, :tenant_subdomains, :mail_from_name, :mail_from_address]
    end

    update :reconfigure do
      accept [:public_url, :tenant_subdomains, :mail_from_name, :mail_from_address]
      require_atomic? false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Slapdash.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Slapdash.Authz.Check
    end
  end

  changes do
    change Slapdash.Instance.Changes.TrimTrailingSlash, on: [:create, :update]
  end

  validations do
    validate Slapdash.Instance.Validations.BaseURL

    validate match(:mail_from_address, ~r/\A[^@\s]+@[^@\s]+\z/) do
      message "must be an email address"
    end
  end

  attributes do
    attribute :id, :integer do
      primary_key? true
      allow_nil? false
      default 1
      writable? false
      public? true
    end

    attribute :public_url, :string do
      description "Base URL people reach Slapdash at, such as https://bot.example.com"
      public? true
    end

    attribute :tenant_subdomains, :boolean do
      description "Whether each tenant is also served at <slug>.<public URL host>"
      allow_nil? false
      default false
      public? true
    end

    attribute :mail_from_name, :string do
      public? true
      default "Slapdash"
    end

    attribute :mail_from_address, :string do
      description "Sender address. Without one, mail comes from noreply@ the public URL's host"
      public? true
    end

    timestamps()
  end
end
