#!/usr/bin/env sh
set -e

# Move default script to /var/scripts if it doesn't exist, otherwise delete tmp file
if [ -f "/tmp/gh-pkg-rollout.sh" ]; then
	if [ -f "/var/scripts/gh-pkg-rollout.sh" ]; then
		rm /tmp/gh-pkg-rollout.sh
	else
		mv /tmp/gh-pkg-rollout.sh /var/scripts/gh-pkg-rollout.sh
	fi
fi

# Make all .sh files in /var/scripts executable (safer than chmod -R +x)
find /var/scripts -name "*.sh" -type f -exec chmod +x {} \;

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
