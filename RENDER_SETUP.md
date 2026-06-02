# Render setup

## Email wipe codes

Use Resend on Render. Set these environment variables:

```text
ROOMS_RESET_RESEND_API_KEY=re_...
ROOMS_RESET_EMAIL_FROM=Rooms Analytics <onboarding@resend.dev>
```

`ROOMS_RESET_EMAIL_FROM` can be your verified Resend sender after you add a domain in Resend.

SMTP still works if your provider supports plain hosted SMTP:

```text
ROOMS_RESET_SMTP_HOST=smtp.example.com
ROOMS_RESET_SMTP_PORT=587
ROOMS_RESET_SMTP_USER=...
ROOMS_RESET_SMTP_PASS=...
ROOMS_RESET_EMAIL_FROM=Rooms Analytics <sender@example.com>
```

Proton Mail normally needs Proton Bridge for SMTP, so it is not a good Render SMTP target.

## Data that survives fresh clones

The dashboard still writes to local `analytics.json` first. To survive fresh clones, new Render instances, and deployments without a persistent disk, add a private GitHub Gist backup.

Create a private Gist with a file named `rooms-analytics.json` containing:

```json
{
  "Version": 1
}
```

Create a fine-scoped GitHub token that can edit gists, then set:

```text
ROOMS_ANALYTICS_GIST_ID=your_gist_id
ROOMS_ANALYTICS_GITHUB_TOKEN=github_pat_or_token
ROOMS_ANALYTICS_GIST_FILE=rooms-analytics.json
```

On startup, the server restores from the Gist when the local file is empty. After every analytics write, it syncs the latest aggregate back to the Gist.
