defmodule Ramshackle.Instance.BootSecrets do
  @moduledoc """
  The secrets Ramshackle generates for itself on first boot: Phoenix's
  `secret_key_base` and the token signing secret for sign-in tokens.

  They are encrypted with the master key (`Ramshackle.Vault`) and never leave
  the server. `Ramshackle.Instance.Boot` loads them at startup. No policy lets
  anyone read or change them; only boot code does, with `authorize?: false`.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  cloak do
    vault Ramshackle.Vault
    attributes [:secret_key_base, :token_signing_secret]
  end

  postgres do
    table "instance_boot_secrets"
    repo Ramshackle.Repo

    check_constraints do
      check_constraint :id, "instance_boot_secrets_singleton", check: "id = 1"
    end
  end

  actions do
    read :current do
      get? true
      filter expr(id == 1)
    end

    create :generate do
      description "Store freshly generated secrets. Runs once, on first boot."
      accept [:secret_key_base, :token_signing_secret]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    attribute :id, :integer do
      primary_key? true
      allow_nil? false
      default 1
      writable? false
    end

    attribute :secret_key_base, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :token_signing_secret, :string do
      allow_nil? false
      sensitive? true
    end

    create_timestamp :inserted_at
  end

  @doc false
  def random_secret, do: 64 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
end
