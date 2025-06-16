#!/usr/bin/env sh
set -e

docker pull $APP_IMAGE
docker rollout $APP_SERVICE_NAME
docker image prune -f

exit 0
