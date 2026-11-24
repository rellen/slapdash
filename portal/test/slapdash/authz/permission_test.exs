defmodule Slapdash.Authz.PermissionTest do
  use ExUnit.Case, async: true

  alias Slapdash.Authz.Permission

  describe "parse!/1" do
    test "parses an allow" do
      assert %Permission{deny?: false, resource: "membership", action: "read", scope: "own"} =
               Permission.parse!("membership:*:read:own")
    end

    test "parses a deny" do
      assert %Permission{deny?: true, resource: "tenant", action: "*", scope: "always"} =
               Permission.parse!("!tenant:*:*:always")
    end

    test "refuses per-record permissions, which are not supported yet" do
      assert_raise ArgumentError, ~r/per-record/, fn ->
        Permission.parse!("tenant:abc:read:always")
      end
    end

    test "refuses malformed strings" do
      for bad <- ["tenant:read:always", "tenant:*:read:", ":*:read:always", "a:b:c:d:e"] do
        assert_raise ArgumentError, fn -> Permission.parse!(bad) end
      end
    end
  end

  describe "matches?/3" do
    test "matches exact names, wildcards and prefixes" do
      read = %{name: :read}
      reconfigure = %{name: :reconfigure}

      assert Permission.matches?(Permission.parse!("tenant:*:read:always"), "tenant", read)
      assert Permission.matches?(Permission.parse!("*:*:*:always"), "tenant", read)
      assert Permission.matches?(Permission.parse!("tenant:*:re*:always"), "tenant", reconfigure)
      refute Permission.matches?(Permission.parse!("tenant:*:read:always"), "membership", read)
      refute Permission.matches?(Permission.parse!("tenant:*:rename:always"), "tenant", read)
    end
  end
end
