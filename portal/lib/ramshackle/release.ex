defmodule Ramshackle.Release do
  @moduledoc """
  Operator tasks for a release, run without Mix.

  Every function works three ways:

  - from `iex -S mix` in development, against the running app;
  - from `bin/ramshackle eval`, with no running node: it starts just the
    database connection and the vault, does its work, and exits. This is the
    way under NixOS and in containers, where Erlang distribution is off;
  - from `bin/ramshackle rpc`, against a running node that has distribution
    on.

  ## Onboarding root

  On a fresh install there are no users and no mail provider, so the first
  sign-in link is printed instead of emailed:

      bin/ramshackle eval 'Ramshackle.Release.create_root("you@example.com", public_url: "https://bot.example.com")'

  Open the printed link to sign in as root, then set up mail, GitHub sign-in
  and tenants under Admin. `public_url` is only needed the first time.

  If you are ever locked out, print a fresh link for any user:

      bin/ramshackle eval 'Ramshackle.Release.sign_in_link("you@example.com")'

  Links are single use and expire after 10 minutes.
  """
  @app :ramshackle

  alias AshAuthentication.Strategy.MagicLink
  alias Ramshackle.Accounts
  alias Ramshackle.Accounts.User
  alias Ramshackle.Instance

  @doc "Runs pending migrations: the public schema's, then each tenant schema's."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)

          for schema <- repo.all_tenants() do
            Ecto.Migrator.run(repo, tenant_migrations_path(repo), :up, all: true, prefix: schema)
          end
        end)
    end

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Makes `email` root, creating the user if needed, and prints a sign-in link.

  Options:

  - `:public_url` - the URL people reach Ramshackle at, such as
    `https://bot.example.com`. Required until it is set, because the link is
    built from it.

  Returns `{:ok, link}` or `{:error, message}`.
  """
  @spec create_root(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def create_root(email, opts \\ []) when is_binary(email) do
    with_instance(fn ->
      with :ok <- maybe_set_public_url(opts[:public_url]),
           :ok <- require_public_url(),
           {:ok, user} <- Accounts.ensure_user(email),
           {:ok, _root} <- Ash.update(user, %{}, action: :make_root, authorize?: false) do
        IO.puts("#{email} is now root.")
        print_link(user)
      end
      |> report()
    end)
  end

  @doc """
  Prints a one-time sign-in link for an existing user, without email.

  For recovery when mail is not set up or not working.
  """
  @spec sign_in_link(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def sign_in_link(email) when is_binary(email) do
    with_instance(fn ->
      with :ok <- require_public_url(),
           {:ok, %User{} = user} <-
             Accounts.get_user_by_email(email, authorize?: false, not_found_error?: false)
             |> found(email) do
        print_link(user)
      end
      |> report()
    end)
  end

  defp found({:ok, nil}, email), do: {:error, "there is no user with the email #{email}"}
  defp found(other, _email), do: other

  defp print_link(user) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)

    case MagicLink.request_token_for(strategy, user) do
      {:ok, token} ->
        link = Instance.url("/magic_link/" <> token)

        IO.puts("""

        Sign in within 10 minutes with this single-use link:

          #{link}
        """)

        {:ok, link}

      _ ->
        {:error, "could not create a sign-in token"}
    end
  end

  defp maybe_set_public_url(nil), do: :ok

  defp maybe_set_public_url(url) do
    result =
      case Instance.get_settings(authorize?: false, not_found_error?: false) do
        {:ok, nil} ->
          Instance.configure_settings(%{public_url: url}, authorize?: false)

        {:ok, settings} ->
          Instance.reconfigure_settings(settings, %{public_url: url}, authorize?: false)

        error ->
          error
      end

    case result do
      {:ok, _} -> :ok
      {:error, error} -> {:error, "could not set the public URL: " <> Exception.message(error)}
    end
  end

  defp require_public_url do
    if Instance.public_url_set?() do
      :ok
    else
      {:error,
       "the public URL is not set yet. Pass it the first time, for example " <>
         ~s|create_root("you@example.com", public_url: "https://bot.example.com")|}
    end
  end

  defp report({:ok, _} = ok), do: ok

  defp report({:error, message}) when is_binary(message) do
    IO.puts(:stderr, "Error: " <> message)
    {:error, message}
  end

  defp report({:error, error}) do
    message = if is_exception(error), do: Exception.message(error), else: inspect(error)
    report({:error, message})
  end

  # Runs `fun` against the running app if there is one. Otherwise starts the
  # dependencies, the repo and the vault, loads the boot secrets, runs `fun`
  # and stops what it started.
  defp with_instance(fun) do
    if Process.whereis(Ramshackle.Supervisor) do
      fun.()
    else
      load_app()

      for app <- Application.spec(@app, :applications) do
        {:ok, _} = Application.ensure_all_started(app)
      end

      children = [Ramshackle.Repo, Ramshackle.Vault, Ramshackle.Instance.Boot]
      {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

      try do
        fun.()
      after
        Supervisor.stop(supervisor)
      end
    end
  end

  defp tenant_migrations_path(repo) do
    repo.config()[:tenant_migrations_path] ||
      Application.app_dir(@app, "priv/repo/tenant_migrations")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
