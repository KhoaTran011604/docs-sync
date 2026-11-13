#!/bin/sh
set -eu

export COPYFILE_DISABLE=1

for cmd in git tar curl sed grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: must be run inside a git repository" >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

DRY_RUN=0
ALLOW_MASS_TRASH=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --allow-mass-trash) ALLOW_MASS_TRASH=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--allow-mass-trash]"
      exit 0
      ;;
    *)
      echo "error: unrecognized argument '$arg'. Usage: $0 [--dry-run] [--allow-mass-trash]" >&2
      exit 1
      ;;
  esac
done

if [ ! -f .erp-docs.config.json ]; then
  echo "error: .erp-docs.config.json not found in repository root" >&2
  exit 1
fi

read_config_field() {
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .erp-docs.config.json | head -n 1
}

CONFIG_ENV_FILE="$(read_config_field "envFile")"
ENV_FILE="${CONFIG_ENV_FILE:-.env.erp-docs}"

resolve_var() {
  var_name="$1"
  val=""
  eval "val=\"\${$var_name:-}\""
  if [ -n "$val" ]; then
    printf '%s' "$val"
    return 0
  fi
  if [ -f "$ENV_FILE" ]; then
    line="$(grep "^${var_name}=" "$ENV_FILE" 2>/dev/null | head -n 1 || true)"
    if [ -n "$line" ]; then
      val="${line#*=}"
      val="$(printf '%s' "$val" | tr -d '\r')"
      case "$val" in
        \"*\") val="${val#\"}"; val="${val%\"}" ;;
        \'*\') val="${val#\'}"; val="${val%\'}" ;;
      esac
      printf '%s' "$val"
      return 0
    fi
  fi
  return 1
}

CONFIG_TOKEN="$(read_config_field "token")"
TOKEN_RAW="${CONFIG_TOKEN:-"\${ERP_DOCS_SYNC_TOKEN}"}"

case "$TOKEN_RAW" in
  "\${"*"}")
    TOKEN_VAR="${TOKEN_RAW#\$\{}"
    TOKEN_VAR="${TOKEN_VAR%\}}"
    case "$TOKEN_VAR" in
      *[!A-Z0-9_]* | "" | [0-9]*)
        echo "error: invalid token placeholder format in config: '$TOKEN_RAW'" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "error: config field \"token\" must be an environment placeholder matching \"\${VAR_NAME}\"" >&2
    exit 2
    ;;
esac

TOKEN="$(resolve_var "$TOKEN_VAR" || true)"
if [ -z "$TOKEN" ]; then
  echo "error: $TOKEN_VAR not set (env or $ENV_FILE)" >&2
  exit 1
fi

CONFIG_API_URL="$(read_config_field "apiUrl")"
API_URL_RAW="${CONFIG_API_URL:-"\${PERMISSION_API_PUBLIC_URL}"}"

case "$API_URL_RAW" in
  "\${"*"}")
    API_URL_VAR="${API_URL_RAW#\$\{}"
    API_URL_VAR="${API_URL_VAR%\}}"
    case "$API_URL_VAR" in
      *[!A-Z0-9_]* | "" | [0-9]*)
        echo "error: invalid apiUrl placeholder format in config: '$API_URL_RAW'" >&2
        exit 2
        ;;
    esac
    API_URL="$(resolve_var "$API_URL_VAR" || true)"
    if [ -z "$API_URL" ]; then
      echo "error: $API_URL_VAR not set (env or $ENV_FILE)" >&2
      exit 1
    fi
    ;;
  *)
    API_URL="$API_URL_RAW"
    ;;
esac

case "$API_URL" in
  http://localhost* | http://127.0.0.1*) ;;
  http://*)
    echo "warning: apiUrl uses unencrypted http://; https:// is strongly recommended in production." >&2
    ;;
esac

TARGET_URL="${API_URL%/}"
case "$TARGET_URL" in
  */sync-docs) ;;
  *) TARGET_URL="${TARGET_URL}/sync-docs" ;;
esac
BASE_URL="${TARGET_URL%/sync-docs}"

if [ "$DRY_RUN" -eq 1 ]; then
  TARGET_URL="${TARGET_URL}?dryRun=1&async=1"
else
  TARGET_URL="${TARGET_URL}?async=1"
fi
if [ "$ALLOW_MASS_TRASH" -eq 1 ]; then
  TARGET_URL="${TARGET_URL}&allowMassTrash=1"
fi

USE_NULL=0
if tar --null -T /dev/null -cf /dev/null 2>/dev/null; then
  USE_NULL=1
fi

RESP_FILE="$(mktemp 2>/dev/null || mktemp -t erp-docs-resp.XXXXXX 2>/dev/null || echo "/tmp/erp-docs-resp-$$.json")"
TAR_FILE="$(mktemp 2>/dev/null || mktemp -t erp-docs-tar.XXXXXX 2>/dev/null || echo "/tmp/erp-docs-tar-$$.tar.gz")"
trap 'rm -f "$RESP_FILE" "$TAR_FILE"' EXIT INT TERM

if [ "$USE_NULL" -eq 1 ]; then
  {
    git ls-files -z --cached --others --exclude-standard -- .erp-docs.config.json
    git ls-files -z --cached --others --exclude-standard -- \
      ':(icase)*.md' \
      ':(icase)*.png' \
      ':(icase)*.jpg' \
      ':(icase)*.jpeg' \
      ':(icase)*.gif' \
      ':(icase)*.svg' \
      ':(icase)*.webp'
  } | xargs -0 sh -c 'for f do [ -e "$f" ] && printf "%s\0" "$f"; done' _ \
    | tar --null -T - -czf "$TAR_FILE"
else
  {
    git ls-files --cached --others --exclude-standard -- .erp-docs.config.json
    git ls-files --cached --others --exclude-standard -- \
      ':(icase)*.md' \
      ':(icase)*.png' \
      ':(icase)*.jpg' \
      ':(icase)*.jpeg' \
      ':(icase)*.gif' \
      ':(icase)*.svg' \
      ':(icase)*.webp'
  } | while IFS= read -r f; do
    [ -e "$f" ] && printf '%s\n' "$f"
  done | tar -T - -czf "$TAR_FILE"
fi

POLL_INTERVAL=3
POLL_TIMEOUT=900
MAX_POLL_FAILURES=5

# First string value of a key in a compact JSON body ($1=key, $2=file).
json_field() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -n 1 \
    | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/'
}

print_body() {
  if [ -s "$RESP_FILE" ]; then
    cat "$RESP_FILE"
    echo ""
  fi
}

# Print the final body and exit 0 only when the sync reported "ok": true.
finish_with_ok_check() {
  print_body
  if grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$RESP_FILE" 2>/dev/null; then
    exit 0
  fi
  exit 1
}

poll_job() {
  job_id="$1"
  case "$job_id" in
    "" | *[!0-9a-fA-F-]*)
      echo "error: server returned an invalid job id" >&2
      exit 1
      ;;
  esac
  status_url="${BASE_URL}/sync-docs/jobs/${job_id}"
  echo "[docs-sync] job $job_id accepted" >&2

  elapsed=0
  failures=0
  last_status=""
  while [ "$elapsed" -lt "$POLL_TIMEOUT" ]; do
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))

    code="$(curl -sS --max-time 30 -w '%{http_code}' \
      -H "Authorization: Bearer $TOKEN" \
      -o "$RESP_FILE" "$status_url" 2>/dev/null)" || code=""

    case "$code" in
      200) failures=0 ;;
      "" | 000 | 429 | 5??)
        failures=$((failures + 1))
        if [ "$failures" -ge "$MAX_POLL_FAILURES" ]; then
          print_body
          echo "error: lost contact with docs sync API while polling job $job_id (last HTTP '${code:-none}'); check status at $status_url" >&2
          exit 1
        fi
        continue
        ;;
      *)
        print_body
        echo "error: polling job $job_id failed with HTTP $code" >&2
        exit 1
        ;;
    esac

    status="$(json_field status "$RESP_FILE")"
    case "$status" in
      succeeded) finish_with_ok_check ;;
      failed)
        print_body
        exit 1
        ;;
      queued | running)
        if [ "$status" != "$last_status" ]; then
          echo "[docs-sync] job $job_id: $status (elapsed ${elapsed}s)" >&2
          last_status="$status"
        fi
        ;;
    esac
  done

  echo "error: timed out waiting for job $job_id; check status at $status_url" >&2
  exit 1
}

if ! HTTP_CODE="$(curl -sS --max-time 120 -w '%{http_code}' \
  -X POST "$TARGET_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/gzip" \
  --data-binary @"$TAR_FILE" \
  -o "$RESP_FILE")"; then
  echo "error: failed to connect to docs sync API at $TARGET_URL" >&2
  exit 1
fi

case "$HTTP_CODE" in
  202) poll_job "$(json_field jobId "$RESP_FILE")" ;;
  200) finish_with_ok_check ;;
  *)
    print_body
    exit 1
    ;;
esac