# @ktran-1604/docs-sync

One-command setup to sync your Markdown docs to **HD ERP Outline** collections.

---

## ✨ Features

- **Zero config to start** — single `npx` command installs everything
- **Interactive setup** — guided prompts with sensible defaults, no manual file editing
- **Secure by design** — tokens stay in `.env.erp-docs` (never in JSON config), `.gitignore` updated automatically
- **Git-aware sync** — only tracked/staged `.md` and image files are uploaded
- **Dry-run mode** — preview changes before applying with `--dry-run`
- **Self-contained scripts** — plain `sh` + standard POSIX tools (`git`, `tar`, `curl`), no Node.js runtime needed after setup
- **Auto-publish to npm** — GitHub Actions workflow publishes on every new version pushed to `main`

---

## Quick Start

### Option A — one-off (no install)

```sh
npx @ktran-1604/docs-sync
```

### Option B — save to project (recommended for teams)

```sh
npm install --save-dev @ktran-1604/docs-sync
npx docs-sync
```

Package is saved to `devDependencies` so everyone on the team gets it after `npm install`.

You can also add a convenience script to `package.json`:

```json
{
  "scripts": {
    "docs:setup": "docs-sync",
    "docs:sync": "sh scripts/docs-sync/run.sh",
    "docs:sync:dry": "sh scripts/docs-sync/run.sh --dry-run"
  }
}
```

Then run:

```sh
npm run docs:setup   # first-time setup
npm run docs:sync    # sync docs
npm run docs:sync:dry  # preview only
```

---

Follow the prompts:

```
PERMISSION_API_PUBLIC_URL [https://hd-erp-permission.dev.hdwebsoft.co]: 
ERP_DOCS_SYNC_TOKEN: hdk_...
collectionId (UUID): xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Docs directory [docs]: 
```

After setup, run the sync:

```sh
sh scripts/docs-sync/run.sh

# Preview only (no changes)
sh scripts/docs-sync/run.sh --dry-run
```

---

## What Gets Created

| Path | Description |
|------|-------------|
| `scripts/docs-sync/run.sh` | Sync script |
| `scripts/docs-sync/README.md` | Script usage guide |
| `.erp-docs.config.json` | Collection config (safe to commit) |
| `.env.erp-docs` | Secrets — **never commit** |

---

## Configuration

`.erp-docs.config.json` (committed):
```json
{
  "apiUrl": "${PERMISSION_API_PUBLIC_URL}",
  "token": "${ERP_DOCS_SYNC_TOKEN}",
  "envFile": ".env.erp-docs",
  "collectionId": "<your-uuid>",
  "root": "docs/",
  "include": ["docs/**"],
  "exclude": ["docs/internal/**"]
}
```

`.env.erp-docs` (git-ignored):
```env
PERMISSION_API_PUBLIC_URL=https://hd-erp-permission.dev.hdwebsoft.co
ERP_DOCS_SYNC_TOKEN=hdk_your_token
```

---

## Dev / Publishing

```sh
# Bump version, then push to main → GitHub Actions auto-publishes to npm
# Requires NPM_TOKEN secret in repo Settings → Secrets → Actions
```

See `.env.example` for all required secrets.
