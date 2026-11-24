defmodule RamshackleWeb.Router do
  use RamshackleWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RamshackleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", RamshackleWeb do
    pipe_through :browser

    ash_authentication_live_session :admin,
      on_mount: [
        {RamshackleWeb.LiveUserAuth, :live_user_required},
        {RamshackleWeb.LiveUserAuth, :live_root_required}
      ] do
      live "/admin", Admin.SettingsLive
      live "/admin/mail", Admin.MailLive
      live "/admin/github", Admin.GitHubLive
      live "/admin/tenants", Admin.TenantsLive
    end

    ash_authentication_live_session :signed_in,
      on_mount: {RamshackleWeb.LiveUserAuth, :live_user_required} do
      live "/tenants/:slug/members", Tenants.MembersLive
    end
  end

  scope "/", RamshackleWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Callbacks and form targets for the magic link and GitHub strategies,
    # under /auth/user/...
    auth_routes AuthController, Ramshackle.Accounts.User, path: "/auth"

    get "/sign-in", SignInController, :new
    get "/magic_link/:token", SignInController, :magic_link
    delete "/sign-out", AuthController, :sign_out
  end

  # Other scopes may use custom stacks.
  # scope "/api", RamshackleWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ramshackle, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RamshackleWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
