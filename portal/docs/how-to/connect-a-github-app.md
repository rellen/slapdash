# Connect a GitHub App and turn on the Greeter bot

This guide connects a tenant to GitHub with a GitHub App. At the end, the
Greeter bot puts a comment on each new pull request of a repository.

You need:

- A Slapdash install that GitHub can reach over HTTPS. Root sets its public
  URL at `/admin`. The webhook URL uses it.
- The administrator role in the tenant, or root.
- Permission to make a GitHub App on a GitHub account or organization, and
  to install it on the repository.

The examples use the tenant `acme` and the repository `octo-org/hello`.

## 1. Make the GitHub App

1. In GitHub, open **Settings**, **Developer settings**, **GitHub Apps**,
   and click **New GitHub App**. For an organization, open the settings of
   the organization.
2. Give the app a name. GitHub shows comments from the app as
   `<app name>[bot]`.
3. Set **Homepage URL** to the public URL of Slapdash.
4. Under **Webhook**, select **Active**. Leave **Webhook URL** blank for
   now. You get the URL in step 2.
5. Make a long random **Webhook secret**, for example with
   `openssl rand -hex 32`. Keep it for step 2.
6. Under **Permissions**, **Repository permissions**, set **Pull requests**
   to **Read and write**.
7. Under **Subscribe to events**, select **Pull request**.
8. Select who can install the app, and click **Create GitHub App**.
9. On the page of the new app, write down the **App ID**.
10. Under **Private keys**, click **Generate a private key**. GitHub
    downloads a `.pem` file.

## 2. Add the connection in Slapdash

1. Open `/tenants/acme/connections` and click
   **Add a GitHub App connection**.
2. Fill in the form:
   - **Name**: a name for people, for example `GitHub`.
   - **App ID**: the number from step 1.
   - **GitHub web URL** and **GitHub API URL**: keep the defaults for
     github.com. For GitHub Enterprise Server, use `https://<host>` and
     `https://<host>/api/v3`.
   - **Private key**: paste all of the `.pem` file.
   - **Webhook secret**: the secret from step 1.
3. Click **Save connection**. The page now shows the webhook URL of the
   connection, for example
   `https://slapdash.example.com/webhooks/0f6c…`.
4. Delete the `.pem` file from your computer. Slapdash keeps the key
   encrypted, and it never shows the key again.

## 3. Give the webhook URL to GitHub

1. In GitHub, open the settings of the app.
2. Paste the webhook URL into **Webhook URL**. Keep the content type
   `application/json`.
3. Click **Save changes**.

## 4. Install the app on the repository

1. On the page of the app, click **Install App**.
2. Select the account, then **Only select repositories**, and select
   `octo-org/hello`.
3. Click **Install**.

## 5. Add the repository and turn on the bot

1. Open `/tenants/acme/repositories`.
2. Select the connection, type `octo-org/hello` as the path, and click
   **Add repository**. A GitHub URL of the repository also works.
3. In the row of the repository, click **Turn on Greeter**.

## 6. Check the result

1. Open a pull request on `octo-org/hello`.
2. After a few seconds, the app puts the Greeter comment on the pull
   request.
3. Open `/tenants/acme/runs`. The run has the status **Succeeded**.

If no comment comes:

- In GitHub, open the settings of the app, then **Advanced**, **Recent
  Deliveries**. An answer of `401` means that the webhook secret in
  Slapdash is not the same as in GitHub. An answer of `404` means that the
  webhook URL is not correct.
- On `/tenants/acme/runs`, a failed run shows the error from GitHub. The
  error `GitHub answered 404 for GET /repos/octo-org/hello/installation`
  means that the app is not installed on the repository.

See also [the reference for bots and webhooks](../reference/bots-and-webhooks.md)
and [the explanation of the bot framework](../explanation/bot-framework.md).
