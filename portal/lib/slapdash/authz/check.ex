defmodule Slapdash.Authz.Check do
  @moduledoc """
  Authorizes creates, updates, destroys and generic actions. See
  `Slapdash.Authz`.

      policy action_type([:create, :update, :destroy]) do
        authorize_if Slapdash.Authz.Check
      end

  The grants' filter is evaluated against the record: for a create, the
  record as it would be stored; for an update or destroy, the record as it is
  now. A filter that cannot be evaluated in memory (one that follows a
  relationship, say) is checked with a query for that record instead. A
  generic action passes only with an `always` scope.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the actor holds a permission that reaches the record"

  @impl true
  def requires_original_data?(_authorizer, _opts), do: true

  @impl true
  def match?(actor, %{resource: resource, action: action, subject: subject}, _opts) do
    case Slapdash.Authz.filter(actor, resource, action, subject.tenant) do
      true -> true
      false -> false
      filter -> record_matches?(filter, actor, resource, subject)
    end
  end

  defp record_matches?(filter, actor, resource, %Ash.Changeset{} = changeset) do
    filter =
      Ash.Expr.fill_template(filter,
        actor: actor,
        tenant: changeset.to_tenant,
        args: changeset.arguments,
        context: changeset.context
      )

    with {:ok, record} <- record(changeset),
         {:ok, value} <-
           Ash.Expr.eval(filter,
             record: record,
             resource: resource,
             actor: actor,
             tenant: changeset.tenant,
             unknown_on_unknown_refs?: true
           ) do
      value == true
    else
      :unknown -> stored_record_matches?(filter, resource, changeset)
      _ -> false
    end
  end

  defp record_matches?(_filter, _actor, _resource, _subject), do: false

  # An invalid create never reaches the database, so its attributes can still
  # decide authorization. This lets `can_*?` checks pass partial input.
  defp record(%Ash.Changeset{action_type: :create} = changeset),
    do: Ash.Changeset.apply_attributes(changeset, force?: true)

  defp record(%Ash.Changeset{data: %{__meta__: %{state: :loaded}} = data}), do: {:ok, data}
  defp record(_changeset), do: :error

  # Falls back to asking the database whether the stored record matches.
  defp stored_record_matches?(_filter, _resource, %Ash.Changeset{action_type: :create}),
    do: false

  defp stored_record_matches?(filter, resource, %Ash.Changeset{data: data} = changeset) do
    primary_key = data |> Map.take(Ash.Resource.Info.primary_key(resource)) |> Map.to_list()

    resource
    |> Ash.Query.do_filter(primary_key)
    |> Ash.Query.do_filter(filter)
    |> Ash.exists?(authorize?: false, tenant: changeset.tenant)
  end
end
