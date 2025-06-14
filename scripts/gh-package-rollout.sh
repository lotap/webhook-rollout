#!/usr/bin/env sh
set -e

docker compose pull $ROLLOUT_SERVICE_NAME
docker rollout $ROLLOUT_SERVICE_NAME
docker image prune -f

exit 0
