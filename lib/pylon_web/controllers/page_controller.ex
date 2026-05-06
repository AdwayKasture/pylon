defmodule PylonWeb.PageController do
  use PylonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
