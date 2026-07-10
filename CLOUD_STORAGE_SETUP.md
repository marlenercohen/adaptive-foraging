# Cloudflare storage setup

This project includes a Worker in `cloudflare-worker/` that accepts the completed session JSON and stores it privately in Cloudflare R2.

1. In Cloudflare, create an R2 bucket named `adaptive-foraging-sessions`.
2. Create/deploy the Worker from `cloudflare-worker/` and bind the bucket as `SESSION_BUCKET`.
3. Copy the deployed Worker URL, for example `https://adaptive-foraging-upload.<account>.workers.dev/`.
4. In `index.html`, set `window.APP_RUNTIME.uploadEndpoint` to that URL.
5. Commit and push the changed project to GitHub. GitHub Pages will update automatically.

The Worker accepts uploads only from `https://marlenercohen.github.io`, validates the JSON schema, limits each upload to 25 MB, and does not expose stored objects publicly.

Files are stored under:

`adaptive-foraging/YYYY/MM/DD/<session_id>.json`
