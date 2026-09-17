# Cloudflare Worker production deployment

The LexPDF Cloudflare Worker is deployed from `develop` by `.github/workflows/cloudflare-deploy.yml`.

## Required GitHub production secrets

- `CLOUDFLARE_API_TOKEN` — Cloudflare API token with permission to deploy the `lexpdf-api` Worker and manage Worker secrets.
- `CLOUDFLARE_ACCOUNT_ID` — Cloudflare account identifier.
- `SUPABASE_SECRET_KEY` — Supabase server-side secret/service credential. It is synchronized to Cloudflare as an encrypted Worker secret and must never be compiled into the application.

`SUPABASE_PUBLISHABLE_KEY` is intentionally stored as a normal Worker variable because it is a publishable client key, not a secret.

## Pipeline behavior

- Pull requests that touch the Worker run TypeScript/contracts and `wrangler deploy --dry-run`.
- Pushes to `develop` affecting the backend or this workflow deploy production after validation.
- Manual `workflow_dispatch` can redeploy the current branch revision.
- Production deploys are serialized with a concurrency group.
- After deployment, `/health` must report `service=lexpdf-api`, `status=ok`, and `ai=true`.
- `/v1/ai/explain` is probed without credentials and must return HTTP 401, proving the new route is live and authentication remains enforced.

## Worker URL

`https://lexpdf-api.d3-concursos.workers.dev`
