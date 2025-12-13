#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Migrates a Docker Compose Postgres named volume from PG17 -> PG18 via pg_dumpall.

Defaults are tuned for this repo's production `docker-compose-noenv.yml`.

Usage:
  bash script/pg18_migrate_compose_volume.sh [options]

Options:
  --compose-file PATH        Compose file (default: docker-compose-noenv.yml)
  --project NAME             Compose project name (default: from compose 'name:', else env COMPOSE_PROJECT_NAME, else current dir)
  --source-key NAME          Compose volume key for the existing PG17 data (default: postgres-data)
  --target-key NAME          Compose volume key for the new PG18 data (default: postgres-data-pg18)
  --source-image IMAGE       PG17 image used to read the old volume (default: pgvector/pgvector:pg17-trixie)
  --target-image IMAGE       PG18 image used to initialize the new volume (default: pgvector/pgvector:pg18-trixie)
  --db-user USER             Postgres superuser (default: postgres)
  --db-password PASSWORD     Password used when initializing the new PG18 cluster (default: env DB_PASSWORD, else postgres)
  --dump-file PATH           Where to write the compressed dump (default: ./tmp/pg17_dumpall_<project>_<timestamp>.sql.gz)
  --skip-down                Don't run `docker compose down` before migrating (default: off)

Examples:
  # Production (no env file)
  DB_PASSWORD='...' bash script/pg18_migrate_compose_volume.sh

  # Devcontainer (keeps the old PG17 dev volume intact)
  bash script/pg18_migrate_compose_volume.sh --compose-file .devcontainer/compose.yaml --db-password postgres
EOF
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if docker-compose version >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi
  echo ""
}

parse_project_from_compose_name() {
  local compose_file="$1"
  # Works for lines like: name: "gray_oak_academy_devcontainer"
  awk -F: 'BEGIN{found=0} /^[[:space:]]*name:[[:space:]]*/{found=1; $1=""; sub(/^[[:space:]]*/, "", $0); gsub(/"/, "", $0); print $0; exit} END{if(!found) exit 1}' "$compose_file" 2>/dev/null || true
}

resolve_volume_name() {
  local project="$1"
  local volume_key="$2"

  # Compose-managed volumes are labeled; prefer label lookup.
  local labeled
  labeled="$(docker volume ls -q --filter "label=com.docker.compose.project=${project}" --filter "label=com.docker.compose.volume=${volume_key}" | head -n 1 || true)"
  if [[ -n "${labeled}" ]]; then
    echo "${labeled}"
    return
  fi

  # Fallbacks for non-labeled or older volumes.
  if docker volume inspect "${project}_${volume_key}" >/dev/null 2>&1; then
    echo "${project}_${volume_key}"
    return
  fi

  if docker volume inspect "${volume_key}" >/dev/null 2>&1; then
    echo "${volume_key}"
    return
  fi

  echo ""
}

wait_for_pg() {
  local container_name="$1"
  local db_user="$2"

  for _ in {1..60}; do
    if docker exec -u postgres "${container_name}" pg_isready -U "${db_user}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

COMPOSE_FILE="docker-compose-noenv.yml"
PROJECT=""
SOURCE_KEY="postgres-data"
TARGET_KEY="postgres-data-pg18"
SOURCE_IMAGE="pgvector/pgvector:pg17-trixie"
TARGET_IMAGE="pgvector/pgvector:pg18-trixie"
DB_USER="postgres"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DUMP_FILE=""
SKIP_DOWN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --compose-file) COMPOSE_FILE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --source-key) SOURCE_KEY="$2"; shift 2 ;;
    --target-key) TARGET_KEY="$2"; shift 2 ;;
    --source-image) SOURCE_IMAGE="$2"; shift 2 ;;
    --target-image) TARGET_IMAGE="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    --dump-file) DUMP_FILE="$2"; shift 2 ;;
    --skip-down) SKIP_DOWN=1; shift ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}" >&2
  exit 1
fi

COMPOSE="$(compose_cmd)"
if [[ -z "${COMPOSE}" ]]; then
  echo "Neither 'docker compose' nor 'docker-compose' is available." >&2
  exit 1
fi

if [[ -z "${PROJECT}" ]]; then
  PROJECT="$(parse_project_from_compose_name "${COMPOSE_FILE}")"
fi
if [[ -z "${PROJECT}" ]]; then
  PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$(pwd)")}"
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
mkdir -p tmp
if [[ -z "${DUMP_FILE}" ]]; then
  DUMP_FILE="tmp/pg17_dumpall_${PROJECT}_${timestamp}.sql.gz"
fi

SOURCE_VOL="$(resolve_volume_name "${PROJECT}" "${SOURCE_KEY}")"
if [[ -z "${SOURCE_VOL}" ]]; then
  echo "Could not find source volume for key '${SOURCE_KEY}' (project '${PROJECT}')." >&2
  echo "Try passing --project, or check: docker volume ls | rg '${SOURCE_KEY}'" >&2
  exit 1
fi

TARGET_VOL="$(resolve_volume_name "${PROJECT}" "${TARGET_KEY}")"
if [[ -n "${TARGET_VOL}" ]]; then
  echo "Target volume already exists for key '${TARGET_KEY}' (resolved: ${TARGET_VOL})." >&2
  echo "Refusing to overwrite. Pick a different --target-key or delete the target volume." >&2
  exit 1
fi
TARGET_VOL="${PROJECT}_${TARGET_KEY}"

if [[ "${SKIP_DOWN}" -eq 0 ]]; then
  ${COMPOSE} -f "${COMPOSE_FILE}" -p "${PROJECT}" down --remove-orphans
fi

SRC_CONT="pg17_dump_${PROJECT}_${timestamp}"
DST_CONT="pg18_restore_${PROJECT}_${timestamp}"

cleanup() {
  docker rm -f "${SRC_CONT}" >/dev/null 2>&1 || true
  docker rm -f "${DST_CONT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Dumping from ${SOURCE_VOL} using ${SOURCE_IMAGE} -> ${DUMP_FILE}"
docker run -d --name "${SRC_CONT}" -e POSTGRES_PASSWORD="${DB_PASSWORD}" -v "${SOURCE_VOL}:/var/lib/postgresql/data" "${SOURCE_IMAGE}" >/dev/null

if ! wait_for_pg "${SRC_CONT}" "${DB_USER}"; then
  echo "PG17 container did not become ready; check logs: docker logs ${SRC_CONT}" >&2
  exit 1
fi

docker exec -u postgres "${SRC_CONT}" pg_dumpall -U "${DB_USER}" | gzip > "${DUMP_FILE}"

echo "Restoring into ${TARGET_VOL} using ${TARGET_IMAGE}"
# Postgres 18+ stores data under major-version subdirs, so mount /var/lib/postgresql (not /var/lib/postgresql/data).
docker run -d --name "${DST_CONT}" -e POSTGRES_PASSWORD="${DB_PASSWORD}" -v "${TARGET_VOL}:/var/lib/postgresql" "${TARGET_IMAGE}" >/dev/null

if ! wait_for_pg "${DST_CONT}" "${DB_USER}"; then
  echo "PG18 container did not become ready; check logs: docker logs ${DST_CONT}" >&2
  exit 1
fi

# pg_dumpall includes role/database creation; restoring into a freshly-initialized cluster can produce a small number of non-fatal conflicts.
# Filter out "CREATE ROLE postgres;" to avoid conflict with the existing superuser
gzip -dc "${DUMP_FILE}" | sed -E '/CREATE ROLE "?postgres"?;/d' | docker exec -i -u postgres "${DST_CONT}" psql -U "${DB_USER}" >/dev/null

restored_dbs="$(docker exec -u postgres "${DST_CONT}" psql -U "${DB_USER}" -tAc "SELECT count(*) FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');" | tr -d '[:space:]')"
if [[ "${restored_dbs}" == "0" || -z "${restored_dbs}" ]]; then
  echo "Restore did not create any non-template databases; investigate the dump/restore output." >&2
  exit 1
fi

echo "Done."
echo " - Source volume preserved: ${SOURCE_VOL}"
echo " - New PG18 volume created: ${TARGET_VOL}"
echo " - Dump file: ${DUMP_FILE}"
echo
echo "Next:"
echo " - Ensure your compose file mounts '${TARGET_KEY}' at /var/lib/postgresql (this repo does)."
echo " - Start the stack: ${COMPOSE} -f ${COMPOSE_FILE} -p ${PROJECT} up -d"
