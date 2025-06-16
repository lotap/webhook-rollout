#!/usr/bin/env sh
set -e

# Login to a registry if credentials are provided
if [ -f "/run/secrets/REGISTRY_PASSWORD" ] && [ -n "$REGISTRY_USERNAME" ] && [ -n "$REGISTRY_URL" ]; then
	cat /run/secrets/REGISTRY_PASSWORD | docker login --username "$REGISTRY_USERNAME" --password-stdin "$REGISTRY_URL"
fi

# Set the environment variable for the webhook secret if provided
if [ -f "/run/secrets/WEBHOOK_SECRET" ]; then
	WEBHOOK_SECRET="$(cat /run/secrets/WEBHOOK_SECRET)"
	export WEBHOOK_SECRET
fi

exec webhook -hooks=/etc/webhook/config.yaml -template
