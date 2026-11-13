defmodule ExWeb.PageController do
  use ExWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
