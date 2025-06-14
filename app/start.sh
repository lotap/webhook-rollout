#!/usr/bin/env sh
set -e

cat /run/secrets/GH_TOKEN | docker login --username "$GH_USERNAME" --password-stdin ghcr.io

WEBHOOK_SECRET="$(cat /run/secrets/WEBHOOK_SECRET)"

export WEBHOOK_SECRET

exec webhook -hooks=/etc/webhook/config.yaml -template
