defmodule Ramshackle.Instance.BootTest do
  # Changes the application environment, so not async.
  use Ramshackle.DataCase, async: false

  alias Ramshackle.Instance.Boot

  setup do
    # Restored after each test.
    for {app, key} <- [
          {:ramshackle, :token_signing_secret},
          {:ramshackle, RamshackleWeb.Endpoint},
          {:ash, :keyset_signing_secret}
        ] do
      Shoddy.Tests.put_app_env(app, key, Application.get_env(app, key))
    end

    # Production runs with async loads on; first boot once crashed only there.
    Shoddy.Tests.put_app_env(:ash, :disable_async?, false)
    Shoddy.Tests.put_app_env(:ramshackle, :boot_secrets, :database)
  end

  test "first boot generates secrets, stores them encrypted and uses them; later boots reuse them" do
    :ok = Boot.load!()

    token_secret = Application.fetch_env!(:ramshackle, :token_signing_secret)
    key_base = Application.fetch_env!(:ramshackle, RamshackleWeb.Endpoint)[:secret_key_base]

    assert byte_size(key_base) >= 64
    assert byte_size(token_secret) >= 64
    assert key_base != token_secret

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_secret_key_base FROM instance_boot_secrets")

    refute stored =~ key_base

    :ok = Boot.load!()
    assert Application.fetch_env!(:ramshackle, :token_signing_secret) == token_secret
  end

  test "nobody can read the boot secrets through Ash" do
    :ok = Boot.load!()
    root = Ramshackle.Fixtures.root()

    result =
      Ramshackle.Instance.BootSecrets
      |> Ash.Query.for_read(:current, %{}, actor: root)
      |> Ash.read_one()

    assert result in [{:ok, nil}] or match?({:error, %Ash.Error.Forbidden{}}, result)
  end
end
