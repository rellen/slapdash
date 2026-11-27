defmodule SlapdashWeb.Tenants.RunsLiveTest do
  use SlapdashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slapdash.Fixtures

  test "members see the latest runs", %{conn: conn} do
    acme = tenant("acme")
    engineer = user()
    member(engineer, acme, :engineer)
    repository = repository(connection(acme))
    enrollment(repository)

    {:ok, _view, html} = conn |> log_in(engineer) |> live(~p"/acme/runs")
    assert html =~ "No bot has run yet."

    {:ok, [run]} = Slapdash.Bots.dispatch(pull_request_opened(repository), repository)
    {:ok, _view, html} = conn |> log_in(engineer) |> live(~p"/acme/runs")

    assert html =~ "run-#{run.id}"
    assert html =~ "Echo"
    assert html =~ "Pull request #7 opened"
    assert html =~ "Queued"
  end
end
