# Render setup

For the Wispbyte migration, use [WISPBYTE_SETUP.md](WISPBYTE_SETUP.md). Existing Render variables remain supported for compatibility.

## Private dashboard

Set `ROOMS_DASHBOARD_CODE` to a long private code and share it only with approved viewers. The dashboard fails closed when this variable is missing. Set `NODE_ENV=production` on Render so the eight-hour, HttpOnly session cookie requires HTTPS. Restarting the server revokes all sessions; change the code and restart to revoke access. Login attempts are limited to ten per socket address per fifteen minutes (viewers behind the same reverse proxy may share that limit).

Keep `ROOMS_ANALYTICS_TOKEN` separate: it must match the existing `ServerStorage.AnalyticsBackendToken` in Roblox. There is no default upload token. The dashboard code is never sent to Roblox or embedded in public JavaScript. `.env.example` documents the variables; the app reads environment variables, so a local file can be loaded with `node --env-file=.env server.js`.

All dashboard files, analytics aliases, and wipe routes require a signed-in session. `/health` and token-authenticated `/api/ingest` remain available to the host and Roblox. Demo data cannot overwrite real analytics. Sign out using the dashboard button.

## Telemetry delivery and game source

`roblox/` contains the replacements applied to the confirmed Rooms dev Studio. See `roblox/STATUS.md` for verification and remaining coverage limits. Keep the existing backend URL, upload token, entity assets, lighting, and effects. The Studio changes have not been published to Roblox.

Deploy the backend before the updated game scripts. Uploads contain authoritative DataStore aggregates. `Revision` equals the cumulative session count; repeated and older revisions are acknowledged without replacing newer data. Legacy snapshots use `TotalSessions` as their revision. Individual session deltas receive HTTP 422 because mixing them with snapshots loses or double-counts sessions. Existing older game servers can therefore lose a session if their DataStore write fails; update the game scripts as part of rollout.

The updated game retries DataStore writes and HTTP uploads three times and republishes stored totals every ten minutes. Random, short-lived retry identifiers stay in DataStore and are stripped from uploads. Deaths are counted once per Humanoid death with entity attribution, and rooms travelled means distinct visited room numbers during the consenting session. Opting out discards that session's pending telemetry; opting back in begins fresh. Earlier aggregate totals retain their original definitions. Exhausted DataStore retries are logged and can still lose that session; there is no durable offline queue.

`TelemetryService` exposes `LastUploadUtc` and `UploadFailures` attributes for server diagnostics. The dashboard shows upload freshness and keeps its last loaded data if refreshing fails. It does not substitute sample statistics.

Run `npm test` for isolated HTTP regression tests. Live Play/Client testing is still required before publishing the game changes.

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
