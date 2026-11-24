defmodule Ramshackle.Instance.Settings do
  @moduledoc """
  Install-wide settings: the public URL Ramshackle is reached at, and the
  sender used for outgoing mail. There is at most one row.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Ramshackle.Authz.Resource]

  authz do
    resource_name("instance_settings")
  end

  postgres do
    table "instance_settings"
    repo Ramshackle.Repo

    check_constraints do
      check_constraint :id, "instance_settings_singleton", check: "id = 1"
    end
  end

  actions do
    defaults [:read]

    read :current do
      get? true
      filter expr(id == 1)
    end

    create :configure do
      accept [:public_url, :mail_from_name, :mail_from_address]
    end

    update :reconfigure do
      accept [:public_url, :mail_from_name, :mail_from_address]
      require_atomic? false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Ramshackle.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Ramshackle.Authz.Check
    end
  end

  changes do
    change Ramshackle.Instance.Changes.TrimTrailingSlash, on: [:create, :update]
  end

  validations do
    validate Ramshackle.Instance.Validations.BaseURL

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
      description "Base URL people reach Ramshackle at, such as https://bot.example.com"
      public? true
    end

    attribute :mail_from_name, :string do
      public? true
      default "Ramshackle"
    end

    attribute :mail_from_address, :string do
      description "Sender address. Without one, mail comes from noreply@ the public URL's host"
      public? true
    end

    timestamps()
  end
end
