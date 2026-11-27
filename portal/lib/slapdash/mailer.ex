defmodule Slapdash.Mailer do
  @moduledoc """
  Sends mail with the provider root configured (`Slapdash.Instance.MailProvider`).

  The provider is read on every send, so changes apply without a restart.
  Without one, the adapter in the application environment is used if there
  is one: `Swoosh.Adapters.Local` in development (see `/dev/mailbox`) and
  `Swoosh.Adapters.Test` in tests. Production sets none, so sending fails
  with `{:error, :mail_not_configured}` until root sets up a provider.

  This calls `Swoosh.Mailer.deliver/2` directly rather than defining a mailer
  with `use Swoosh.Mailer`, because a mailer module puts its config, provider
  credentials included, in the metadata of its telemetry events.
  """

  use Boundary, top_level?: true, deps: [Slapdash.Instance]

  alias Slapdash.Instance

  @doc "Sets the configured sender on an email and delivers it."
  @spec deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%Swoosh.Email{} = email) do
    with {:ok, config} <- config() do
      email
      |> Swoosh.Email.from(from())
      |> Swoosh.Mailer.deliver(config)
    end
  end

  @doc "Like `deliver/1`, but raises if the mail cannot be sent."
  @spec deliver!(Swoosh.Email.t()) :: term()
  def deliver!(email) do
    case deliver(email) do
      {:ok, result} -> result
      {:error, reason} -> raise Swoosh.DeliveryError, reason: reason
    end
  end

  @doc "Whether mail can be sent: a provider is configured, or a fallback adapter is."
  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _}, config())

  defp config do
    case Instance.get_mail_provider(authorize?: false, load: [:secret], not_found_error?: false) do
      {:ok, %Instance.MailProvider{} = provider} ->
        {:ok, Instance.MailProvider.swoosh_config(provider)}

      _ ->
        fallback = Application.get_env(:slapdash, __MODULE__, [])

        if fallback[:adapter],
          do: {:ok, fallback},
          else: {:error, :mail_not_configured}
    end
  end

  @doc """
  The sender: the name and address from `Slapdash.Instance.Settings`, or
  `noreply@` the public URL's host.
  """
  @spec from() :: {String.t(), String.t()}
  def from do
    settings =
      case Instance.get_settings(authorize?: false, not_found_error?: false) do
        {:ok, %Instance.Settings{} = settings} -> settings
        _ -> %Instance.Settings{}
      end

    address = settings.mail_from_address || "noreply@#{URI.parse(Instance.public_url()).host}"
    {settings.mail_from_name || "Slapdash", address}
  end
end
