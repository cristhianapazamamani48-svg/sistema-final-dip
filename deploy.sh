#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash deploy.sh <backend|frontend> <40-character-commit-sha>" >&2
  exit 2
fi

service="$1"
image_tag="$2"

if [[ ! "$image_tag" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "The image tag must be a 40-character commit SHA." >&2
  exit 2
fi

case "$service" in
  backend)
    compose_service=api
    tag_variable=BACKEND_TAG
    ;;
  frontend)
    compose_service=frontend
    tag_variable=FRONTEND_TAG
    ;;
  *)
    echo "Service must be backend or frontend." >&2
    exit 2
    ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

for file in .env versions.env compose.yaml; do
  if [[ ! -f "$file" ]]; then
    echo "Required deployment file is missing: $file" >&2
    exit 1
  fi
done

exec 9>.deploy.lock
if ! flock -w 300 9; then
  echo "Timed out waiting for another deployment to finish." >&2
  exit 1
fi

old_tag="$(sed -n "s/^${tag_variable}=//p" versions.env | head -n 1)"
if [[ -z "$old_tag" ]]; then
  echo "No previous ${tag_variable} value exists in versions.env." >&2
  exit 1
fi

compose=(docker compose --env-file .env --env-file versions.env -f compose.yaml)
rollback() {
  status=$?
  trap - EXIT

  if [[ $status -ne 0 ]]; then
    echo "Deployment failed; restoring ${service} image ${old_tag}." >&2
    export "${tag_variable}=${old_tag}"
    if ! "${compose[@]}" pull "$compose_service" ||
      ! "${compose[@]}" up -d --wait --wait-timeout 120 "$compose_service"; then
      echo "Automatic rollback failed; inspect the Compose services on the server." >&2
    fi
  fi

  exit "$status"
}
trap rollback EXIT

export "${tag_variable}=${image_tag}"
"${compose[@]}" pull "$compose_service"
"${compose[@]}" up -d --wait --wait-timeout 180 "$compose_service"

sed -i "s/^${tag_variable}=.*/${tag_variable}=${image_tag}/" versions.env
trap - EXIT

echo "Deployed ${service} image tag ${image_tag} successfully."
