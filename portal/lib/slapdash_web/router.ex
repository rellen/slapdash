defmodule SlapdashWeb.Router do
  use SlapdashWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SlapdashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", SlapdashWeb do
    pipe_through :browser

    ash_authentication_live_session :admin,
      on_mount: [
        {SlapdashWeb.LiveUserAuth, :live_user_required},
        {SlapdashWeb.LiveUserAuth, :live_root_required}
      ] do
      live "/admin", Admin.SettingsLive
      live "/admin/mail", Admin.MailLive
      live "/admin/github", Admin.GitHubLive
      live "/admin/tenants", Admin.TenantsLive
    end
  end

  scope "/", SlapdashWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Callbacks and form targets for the magic link and GitHub strategies,
    # under /auth/user/...
    auth_routes AuthController, Slapdash.Accounts.User, path: "/auth"

    get "/sign-in", SignInController, :new
    get "/magic_link/:token", SignInController, :magic_link
    delete "/sign-out", AuthController, :sign_out
  end

  # Outside services post webhooks here. There is no session and no CSRF
  # token: the provider checks the signature of each request.
  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/webhooks", SlapdashWeb do
    pipe_through :webhook

    post "/:connection_id", WebhookController, :receive
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:slapdash, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SlapdashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Tenant pages. They come last, because `/:slug/...` matches many paths.
  # Slapdash.Tenancy.Tenant reserves slugs that clash with the routes above.
  # The first group is for tenant subdomains, and the second group works on
  # any host. See SlapdashWeb.TenantScope.
  scope "/", SlapdashWeb do
    pipe_through :browser

    ash_authentication_live_session :tenant,
      on_mount: [
        {SlapdashWeb.LiveUserAuth, :live_user_required},
        SlapdashWeb.TenantScope
      ] do
      live "/members", Tenants.MembersLive
      live "/connections", Tenants.ConnectionsLive, :index
      live "/connections/new/:provider", Tenants.ConnectionsLive, :new
      live "/connections/:id", Tenants.ConnectionsLive, :edit
      live "/repositories", Tenants.RepositoriesLive
      live "/runs", Tenants.RunsLive

      live "/:slug/members", Tenants.MembersLive
      live "/:slug/connections", Tenants.ConnectionsLive, :index
      live "/:slug/connections/new/:provider", Tenants.ConnectionsLive, :new
      live "/:slug/connections/:id", Tenants.ConnectionsLive, :edit
      live "/:slug/repositories", Tenants.RepositoriesLive
      live "/:slug/runs", Tenants.RunsLive
    end
  end
end
