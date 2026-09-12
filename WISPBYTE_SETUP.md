# Wispbyte setup

1. Select Node 22.21+ or 24.10+ and use `server.js` as the startup file (`node server.js`, or `npm start`). There are no external npm dependencies.
2. Upload `server.js`, `hosting.js`, `access.js`, `package.json`, and the `public/` folder using Files or SFTP. Keep the private `.env` outside `public/`; it loads automatically. Panel variables override matching `.env` values.
3. Use the panel's allocated web port. `SERVER_PORT` takes precedence over `PORT`; otherwise set `PORT` explicitly to that allocation. The listener binds `0.0.0.0`. Do not use the SFTP port. Exact allocation and public URL come from your panel.
4. Preserve your existing `ROOMS_DASHBOARD_CODE` and `ROOMS_ANALYTICS_TOKEN`. Set `NODE_ENV=production` and use your HTTPS public URL so secure login cookies work. Keep Resend/SMTP and optional Gist backup settings if you use them.
5. Stop the old host before copying its latest `data/analytics.json` to the new host. Also copy the backup if available. Keep that data directory outside `public/`; use `ROOMS_ANALYTICS_DATA_DIR=./data` or an absolute mounted path. Do not replace production data with the repository's older snapshot. The optional Gist backup still works on Wispbyte.
6. Start the service. Check `/health`, sign in, and verify the existing totals. Then set the existing Roblox `AnalyticsBackendUrl` StringValue to `https://YOUR-PUBLIC-HOST/api/ingest`, keeping its token unchanged. Publish the game when ready.

The new public URL has not been assumed or changed in Studio. A host migration can require DNS/proxy setup outside this repository. SIGTERM/SIGINT drain HTTP requests and attempt the pending remote backup, with a 15-second shutdown deadline; local analytics writes are synchronous.

References: [Wispbyte startup and environment variables](https://wispbyte.com/how-to-host-discord-bot-wispbyte), [Wispbyte file access](https://wispbyte.com/kb/sftp-files). Allocated-port variable compatibility is implemented in this app; the exact variable provided by your selected server image must be checked in the panel.
