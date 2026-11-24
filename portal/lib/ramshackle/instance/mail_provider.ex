defmodule Ramshackle.Instance.MailProvider do
  @moduledoc """
  How Ramshackle sends mail: an SMTP server or one of the API providers
  Swoosh supports. There is at most one.

  `Ramshackle.Mailer` reads it when it sends, so changes apply without a
  restart. The password or API key is encrypted with the master key and is
  never shown again after it is saved; leaving it blank when reconfiguring
  keeps the old one.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak, Ramshackle.Authz.Resource]

  @fields [:adapter, :host, :port, :username, :security, :domain, :region, :secret]

  authz do
    resource_name("mail_provider")
  end

  cloak do
    vault Ramshackle.Vault
    attributes [:secret]
    encrypt_nil? false
  end

  postgres do
    table "mail_provider"
    repo Ramshackle.Repo

    check_constraints do
      check_constraint :id, "mail_provider_singleton", check: "id = 1"
    end
  end

  actions do
    defaults [:read]

    read :current do
      get? true
      filter expr(id == 1)
    end

    create :configure do
      accept @fields

      validate present(:secret),
        where: attribute_in(:adapter, [:postmark, :mailgun, :sendgrid]),
        message: "is required for this provider"
    end

    update :reconfigure do
      accept @fields
      require_atomic? false
      change {Ramshackle.Instance.Changes.KeepSecretWhenBlank, argument: :secret}
    end

    destroy :remove
  end

  policies do
    policy action_type(:read) do
      authorize_if Ramshackle.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Ramshackle.Authz.Check
    end
  end

  validations do
    validate present([:host, :port]), where: attribute_equals(:adapter, :smtp)
    validate present(:domain), where: attribute_equals(:adapter, :mailgun)
    validate numericality(:port, greater_than: 0, less_than: 65_536)
  end

  attributes do
    attribute :id, :integer do
      primary_key? true
      allow_nil? false
      default 1
      writable? false
      public? true
    end

    attribute :adapter, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:smtp, :postmark, :mailgun, :sendgrid]
    end

    attribute :host, :string do
      description "SMTP server host name"
      public? true
    end

    attribute :port, :integer do
      description "SMTP server port, usually 587 for STARTTLS or 465 for TLS"
      public? true
    end

    attribute :username, :string do
      description "SMTP user name. Leave empty if the server needs no login"
      public? true
    end

    attribute :security, :atom do
      description "How the SMTP connection is encrypted"
      allow_nil? false
      public? true
      default :starttls
      constraints one_of: [:starttls, :tls, :none]
    end

    attribute :domain, :string do
      description "Mailgun sending domain"
      public? true
    end

    attribute :region, :atom do
      description "Mailgun region"
      allow_nil? false
      public? true
      default :us
      constraints one_of: [:us, :eu]
    end

    attribute :secret, :string do
      description "SMTP password or provider API key"
      sensitive? true
      public? true
    end

    timestamps()
  end

  @doc """
  The Swoosh configuration for a provider whose `:secret` is loaded.

  The result holds the decrypted secret: pass it straight to Swoosh, and
  never log it or put it in telemetry.
  """
  @spec swoosh_config(Ash.Resource.record()) :: keyword()
  def swoosh_config(%__MODULE__{adapter: :smtp} = provider) do
    host = provider.host

    tls_options = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 10,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    security =
      case provider.security do
        :starttls -> [tls: :always, ssl: false, tls_options: tls_options]
        :tls -> [tls: :never, ssl: true, sockopts: tls_options]
        :none -> [tls: :never, ssl: false]
      end

    login =
      if is_nil(Shoddy.Strings.non_blank(provider.username)) do
        [auth: :never]
      else
        [auth: :always, username: provider.username, password: provider.secret || ""]
      end

    [adapter: Swoosh.Adapters.SMTP, relay: host, port: provider.port, retries: 1] ++
      security ++ login
  end

  def swoosh_config(%__MODULE__{adapter: :postmark, secret: key}),
    do: [adapter: Swoosh.Adapters.Postmark, api_key: key]

  def swoosh_config(%__MODULE__{adapter: :sendgrid, secret: key}),
    do: [adapter: Swoosh.Adapters.Sendgrid, api_key: key]

  def swoosh_config(%__MODULE__{adapter: :mailgun} = provider) do
    base =
      case provider.region do
        :eu -> [base_url: "https://api.eu.mailgun.net/v3"]
        :us -> []
      end

    [adapter: Swoosh.Adapters.Mailgun, api_key: provider.secret, domain: provider.domain] ++
      base
  end
end
