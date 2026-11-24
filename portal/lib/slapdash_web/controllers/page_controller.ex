defmodule SlapdashWeb.PageController do
  use SlapdashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
