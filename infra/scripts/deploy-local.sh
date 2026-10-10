#!/usr/bin/env bash
# Run only from the dedicated checkout on the user-provided server.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CONFIG_FILE:?Set production env file path}"
: "${RELEASE_TAG:?Use a new immutable release tag}"
[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9_.-]+$ ]] || exit 2
COMPOSE_FILE=${COMPOSE_FILE:-infra/compose.production.yaml}
export COMPOSE_FILE RELEASE_TAG CONFIG_FILE
compose=(docker compose --env-file "$CONFIG_FILE" -f "$COMPOSE_FILE")
umask 077
mkdir -p backups
"${compose[@]}" config --quiet
if [[ ${PREBUILT_IMAGES:-0} == 1 ]]; then
  # Imported, verified images are useful where Docker Hub is unreachable.
  docker image inspect "miaoban-api:${RELEASE_TAG}" >/dev/null
else
  "${compose[@]}" build api worker
fi
"${compose[@]}" up -d --wait db
if [[ $("${compose[@]}" exec -T db psql -U miaoban -d miaoban -Atc "SELECT to_regclass('public.wallets') IS NOT NULL") == t ]]; then
  bash infra/scripts/backup.sh
fi
"${compose[@]}" run --rm api alembic upgrade head
if "${compose[@]}" config --services | grep -qx proxy; then
  "${compose[@]}" up -d --wait api worker proxy
else
  "${compose[@]}" up -d --wait api worker
fi
"${compose[@]}" exec -T api python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/ready')"
printf 'release=%s\n' "$RELEASE_TAG" >> backups/releases.log
printf 'Containers ready. Run HTTPS and formal-account smoke acceptance; local health is not a deployment acceptance.\n'
