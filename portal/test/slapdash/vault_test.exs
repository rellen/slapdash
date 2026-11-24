defmodule Slapdash.VaultTest do
  use ExUnit.Case, async: true

  alias Slapdash.Vault

  test "accepts a 32-byte Base64 key" do
    assert byte_size(Vault.decode_key!(Vault.generate_key())) == 32
  end

  test "refuses a missing, short or non-Base64 key without echoing it" do
    for bad <- [nil, Base.encode64("short"), "not base64!!"] do
      error = assert_raise ArgumentError, fn -> Vault.decode_key!(bad) end
      if bad, do: refute(error.message =~ bad)
    end
  end

  test "round-trips and detects tampering" do
    ciphertext = Vault.encrypt!("hello")
    assert Vault.decrypt!(ciphertext) == "hello"

    size = byte_size(ciphertext) - 1
    <<head::binary-size(^size), last>> = ciphertext
    assert_raise Cloak.MissingCipher, fn -> Vault.decrypt!(<<"x", ciphertext::binary>>) end
    tampered = <<head::binary, Bitwise.bxor(last, 1)>>
    assert {:error, %Vault.TamperedError{}} = Vault.decrypt(tampered)
    assert_raise Vault.TamperedError, fn -> Vault.decrypt!(tampered) end
  end
end
