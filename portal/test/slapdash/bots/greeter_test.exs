defmodule Slapdash.Bots.GreeterTest do
  use ExUnit.Case, async: true

  alias Slapdash.Bots.Action.Comment
  alias Slapdash.Bots.{Event, Greeter, Subject}

  test "it asks for the same comment on each opened pull request" do
    event = fn number ->
      %Event{
        id: "e#{number}",
        type: :pull_request_opened,
        connection_id: Ecto.UUID.generate(),
        repository_path: "octo/hello",
        subject: %Subject{kind: :pull_request, number: number, title: "T#{number}"}
      }
    end

    context = %{repository: %{path: "octo/hello", web_url: nil}, settings: %{}}

    assert {:ok, [%Comment{key: "greeter", body: body}]} = Greeter.handle(event.(1), context)
    assert {:ok, [%Comment{body: ^body}]} = Greeter.handle(event.(2), context)
    assert body =~ "ShoddyBot saw this pull request."
  end
end
