defmodule Slapdash.Providers.GitHub.AppTest do
  use Slapdash.DataCase, async: true

  import Slapdash.Fixtures
  import Slapdash.Test.GitHubFixtures

  alias Slapdash.Providers.GitHub.{App, Client}

  setup do
    {key, pem} = rsa_key()
    tenant = tenant()
    %{key: key, pem: pem, tenant: tenant, connection: github_connection(tenant, pem)}
  end

  describe "connection settings" do
    test "the defaults point at github.com", ctx do
      assert ctx.connection.config == %{
               "app_id" => 42,
               "api_url" => "https://api.github.com",
               "web_url" => "https://github.com"
             }
    end

    test "a private key that is not RSA PEM is refused", ctx do
      assert {:error, error} =
               Slapdash.Connections.add_connection(
                 %{
                   tenant_id: ctx.tenant.id,
                   name: "Bad",
                   provider: "github_app",
                   config: %{"app_id" => "1"},
                   secrets: %{"private_key" => "not a key", "webhook_secret" => "x"}
                 },
                 authorize?: false
               )

      assert Exception.message(error) =~ "Private key is not an RSA private key in PEM format"
    end
  end

  describe "repository paths" do
    test "owner/name and GitHub URLs are accepted" do
      assert App.cast_path("octo-org/hello.world") == {:ok, "octo-org/hello.world"}
      assert App.cast_path(" https://github.com/octo/hello.git ") == {:ok, "octo/hello"}
    end

    test "other values are refused" do
      for path <- ["octo", "octo/hello/extra", "-octo/x", "octo/..", "octo/a b", "../x"] do
        assert {:error, _} = App.cast_path(path), "#{path} was accepted"
      end
    end
  end

  test "the app JWT is signed with RS256 and lives for less than ten minutes", ctx do
    jwt = Client.app_jwt(42, ctx.key, 1_000_000)
    [header, claims, signature] = String.split(jwt, ".")

    assert Jason.decode!(Base.url_decode64!(header, padding: false)) ==
             %{"alg" => "RS256", "typ" => "JWT"}

    assert Jason.decode!(Base.url_decode64!(claims, padding: false)) ==
             %{"iat" => 999_940, "exp" => 1_000_540, "iss" => "42"}

    public_key = {:RSAPublicKey, elem(ctx.key, 2), elem(ctx.key, 3)}

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public_key
           )
  end

  describe "webhooks" do
    defp sign(body, secret),
      do: "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    test "the signature is checked with the webhook secret", ctx do
      body = ~s({"zen":"Keep it simple."})
      secrets = %{"webhook_secret" => "whsec"}
      headers = %{"x-hub-signature-256" => sign(body, "whsec")}

      assert App.verify_webhook(ctx.connection, headers, body, secrets) == :ok

      assert {:error, _} =
               App.verify_webhook(
                 ctx.connection,
                 %{"x-hub-signature-256" => sign(body, "no")},
                 body,
                 secrets
               )

      assert {:error, _} = App.verify_webhook(ctx.connection, %{}, body, secrets)
    end

    test "the delivery id and event come from the GitHub headers" do
      headers = %{"x-github-delivery" => "abc-123", "x-github-event" => "pull_request"}

      assert App.parse_webhook(headers, %{}) ==
               {:ok, %{delivery_id: "abc-123", event: "pull_request"}}

      assert {:error, _} = App.parse_webhook(%{}, %{})
    end

    test "an opened pull request becomes an event", ctx do
      payload = %{
        "action" => "opened",
        "pull_request" => %{
          "number" => 5,
          "title" => "Fix it",
          "html_url" => "https://github.com/octo/hello/pull/5",
          "user" => %{"login" => "mona"}
        },
        "repository" => %{"full_name" => "octo/hello"},
        "sender" => %{"login" => "mona"}
      }

      assert [event] = App.to_events("pull_request", payload, ctx.connection)
      assert event.type == :pull_request_opened
      assert event.repository_path == "octo/hello"
      assert event.subject.number == 5
      assert event.subject.author == "mona"

      assert App.to_events("pull_request", %{payload | "action" => "closed"}, ctx.connection) ==
               []

      assert App.to_events("ping", %{}, ctx.connection) == []
    end
  end

  describe "comments" do
    test "a new comment carries a hidden key", ctx do
      stub_github("octo/hello")

      assert App.put_comment(ctx.connection, "octo/hello", 5, "greeter", "Hello") ==
               {:ok, :created}

      assert_received {:github, "GET", "/repos/octo/hello/installation", ""}
      assert_received {:github, "POST", "/app/installations/777/access_tokens", ""}
      assert_received {:github, "GET", "/repos/octo/hello/issues/5/comments", ""}
      assert_received {:github, "POST", "/repos/octo/hello/issues/5/comments", body}
      assert Jason.decode!(body) == %{"body" => "Hello\n\n<!-- slapdash:greeter -->"}
    end

    test "a comment with the key from the app is not posted again", ctx do
      stub_github("octo/hello", [
        %{
          "body" => "Hello\n\n<!-- slapdash:greeter -->",
          "performed_via_github_app" => %{"id" => 42}
        }
      ])

      assert App.put_comment(ctx.connection, "octo/hello", 5, "greeter", "Hello") ==
               {:ok, :exists}

      refute_received {:github, "POST", "/repos/octo/hello/issues/5/comments", _}
    end

    test "a person's comment with the key does not count", ctx do
      stub_github("octo/hello", [
        %{"body" => "<!-- slapdash:greeter -->", "user" => %{"type" => "User"}}
      ])

      assert App.put_comment(ctx.connection, "octo/hello", 5, "greeter", "Hello") ==
               {:ok, :created}
    end

    test "an app that is not installed gives an error without secrets", ctx do
      Req.Test.stub(Client, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert {:error, message} = App.put_comment(ctx.connection, "octo/hello", 5, "k", "x")
      assert message == "GitHub answered 404 for GET /repos/octo/hello/installation: Not Found"
      refute message =~ "PRIVATE KEY"
    end
  end
end
