defmodule RamshackleWeb.PageController do
  use RamshackleWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
