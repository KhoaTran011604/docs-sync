# @khoa-hd/docs-sync

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
npx @khoa-hd/docs-sync
```

### Option B — save to project (recommended for teams)

```sh
npm install --save-dev @khoa-hd/docs-sync
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
CI/CD trigger branch (e.g. dev, main, master - leave blank to skip): main
CI/CD platform (github / gitlab) [github]: github
```

After setup, run the sync:

```sh
sh scripts/docs-sync/run.sh

# Preview only (no changes)
sh scripts/docs-sync/run.sh --dry-run
```

> If you get `error: required command 'sed' not found in PATH`, run it with `bash` instead of `sh`: `bash scripts/docs-sync/run.sh`

If you configured a CI/CD branch, the CLI will automatically generate the pipeline configuration file (`.github/workflows/docs-sync.yml` for GitHub or `.gitlab-ci.yml` for GitLab) and show setup instructions.

---

## What Gets Created

| Path | Description |
|------|-------------|
| `scripts/docs-sync/run.sh` | Sync script |
| `scripts/docs-sync/README.md` | Script usage guide |
| `.erp-docs.config.json` | Collection config (safe to commit) |
| `.env.erp-docs` | Secrets — **never commit** |
| `.github/workflows/docs-sync.yml` | *(Optional)* Auto-generated GitHub Actions workflow |
| `.gitlab-ci.yml` | *(Optional)* Auto-generated / updated GitLab CI config |

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

## CI/CD Integration

### Option 1: GitHub Actions (`.github/workflows/docs-sync.yml`)

The CLI automatically generates this file if you choose `github`:

```yaml
name: HD ERP Docs Sync

on:
  push:
    branches:
      - main  # or dev, master
    paths:
      - 'docs/**'
      - '.erp-docs.config.json'
      - 'scripts/docs-sync/**'
  workflow_dispatch:

jobs:
  sync-docs:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run HD ERP Docs Sync
        env:
          PERMISSION_API_PUBLIC_URL: ${{ vars.PERMISSION_API_PUBLIC_URL || 'https://hd-erp-permission.dev.hdwebsoft.co' }}
          ERP_DOCS_SYNC_TOKEN: ${{ secrets.ERP_DOCS_SYNC_TOKEN }}
        run: |
          chmod +x scripts/docs-sync/run.sh
          sh scripts/docs-sync/run.sh
```

**Secrets & Variables setup on GitHub:**
- Go to repository **Settings** → **Secrets and variables** → **Actions**.
- Under **Repository secrets**, add `ERP_DOCS_SYNC_TOKEN` with your sync token.
- (Optional) Under **Repository variables**, add `PERMISSION_API_PUBLIC_URL` if you need to point to a custom API endpoint.

### Option 2: GitLab CI (`.gitlab-ci.yml`)

The CLI automatically generates or appends to `.gitlab-ci.yml` if you choose `gitlab`:

```yaml
# HD ERP Docs Sync
docs-sync:
  stage: deploy
  image: ubuntu:latest
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - 'docs/**/*'
        - '.erp-docs.config.json'
        - 'scripts/docs-sync/**/*'
  variables:
    PERMISSION_API_PUBLIC_URL: 'https://hd-erp-permission.dev.hdwebsoft.co'
  before_script:
    - apt-get update -qq && apt-get install -y -qq git tar curl sed grep
  script:
    - chmod +x scripts/docs-sync/run.sh
    - sh scripts/docs-sync/run.sh
```

**Variable setup on GitLab:**
- Go to project **Settings** → **CI/CD** → **Variables** (expand).
- Click **Add variable**:
  - Key: `ERP_DOCS_SYNC_TOKEN`
  - Value: `<your sync token>`
  - Type: `Variable` | Check **Mask variable**

---

## Dev / Publishing

```sh
# Bump version, then push to main → GitHub Actions auto-publishes to npm
# Requires NPM_TOKEN secret in repo Settings → Secrets → Actions
```

See `.env.example` for all required secrets.
