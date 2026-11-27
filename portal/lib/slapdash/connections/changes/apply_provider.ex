defmodule Slapdash.Connections.Changes.ApplyProvider do
  @moduledoc """
  Casts and checks a connection's settings and secrets against its
  provider's fields (`Slapdash.Connections.Provider`).

  On an update, the new secrets go on top of the stored ones, so a blank
  secret keeps the stored value. AshCloak encrypts the `secrets` argument
  in a `before_action` hook, which runs after this change.
  """
  use Ash.Resource.Change

  alias Slapdash.Connections.Provider

  @impl true
  def change(changeset, _opts, _context) do
    key = Ash.Changeset.get_attribute(changeset, :provider)

    case Provider.fetch(key) do
      {:ok, provider} -> apply_provider(changeset, provider)
      :error when is_nil(key) -> changeset
      :error -> Ash.Changeset.add_error(changeset, field: :provider, message: "is not known")
    end
  end

  defp apply_provider(changeset, provider) do
    {config, config_errors} =
      Provider.cast(provider, :config, Ash.Changeset.get_attribute(changeset, :config) || %{})

    {new_secrets, secret_errors} =
      Provider.cast(provider, :secrets, submitted_secrets(changeset))

    secrets = Map.merge(stored_secrets(changeset), new_secrets)

    cast_errors = config_errors ++ secret_errors
    failed = MapSet.new(cast_errors, &elem(&1, 0))

    missing =
      (Provider.missing(provider, :config, config) ++
         Provider.missing(provider, :secrets, secrets))
      |> Enum.reject(fn {name, _} -> name in failed end)

    errors = cast_errors ++ missing

    errors =
      if errors == [] and function_exported?(provider, :validate, 2) do
        case provider.validate(config, secrets) do
          :ok -> []
          {:error, errors} -> errors
        end
      else
        errors
      end

    changeset =
      changeset
      |> Ash.Changeset.force_change_attribute(:config, config)
      |> put_secrets(secrets)

    Enum.reduce(errors, changeset, fn {field, message}, changeset ->
      Ash.Changeset.add_error(changeset,
        field: error_field(provider, field),
        message: "#{label(provider, field)} #{message}"
      )
    end)
  end

  # AshCloak turns an accepted cloaked attribute into an argument.
  defp submitted_secrets(changeset) do
    case Ash.Changeset.fetch_argument(changeset, :secrets) do
      {:ok, secrets} when is_map(secrets) -> secrets
      _ -> %{}
    end
  end

  defp stored_secrets(%{action_type: :update, data: data}) do
    Slapdash.Connections.secrets(data)
  end

  defp stored_secrets(_changeset), do: %{}

  defp put_secrets(changeset, secrets) when secrets == %{},
    do: Ash.Changeset.delete_argument(changeset, :secrets)

  defp put_secrets(changeset, secrets),
    do: Ash.Changeset.set_argument(changeset, :secrets, secrets)

  # The error goes on `:"config.<name>"` or `:"secrets.<name>"`, so the form
  # shows it next to its input. Field names come from provider code, so the
  # set of atoms is fixed.
  defp error_field(provider, name) do
    kind =
      case Enum.find(provider.fields(), &(&1.name == name)) do
        %{secret?: true} -> "secrets"
        _ -> "config"
      end

    String.to_atom(kind <> "." <> name)
  end

  defp label(provider, name) do
    case Enum.find(provider.fields(), &(&1.name == name)) do
      %{label: label} -> label
      nil -> name
    end
  end
end
