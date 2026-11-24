defmodule RamshackleWeb.PageControllerTest do
  use RamshackleWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Manage your software repositories"
  end
end
