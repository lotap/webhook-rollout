# webhook-rollout

[![GitHub Release](https://img.shields.io/github/v/release/lotap/webhook-rollout?display_name=tag)](https://github.com/lotap/webhook-rollout/releases) [![Docker Image Version](https://img.shields.io/docker/v/lotap/webhook-rollout?logo=docker&logoColor=white&color=2496ED)](https://hub.docker.com/r/lotap/webhook-rollout)
[![Dependabot Updates](https://github.com/lotap/webhook-rollout/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/lotap/webhook-rollout/actions/workflows/dependabot/dependabot-updates) [![semantic-release: conventionalcommits](https://img.shields.io/badge/semantic--release-conventionalcommits-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)

[webhook](https://github.com/adnanh/webhook) and [docker-rollout](https://github.com/wowu/docker-rollout), 2 great libraries that go great together!

A simple way to **push-to-deploy on any server with docker compose**

## How it works

When you put webhook-rollout on a server, it listens for a webhook request on a specified port (default 9000). You can configure github to build, package, and register an app image when you commit a change. And when the build completes, you can configure github to send the webhook request to your server. From there, [rollout](https://github.com/wowu/docker-rollout) takes over and will automatically handle pulling the newly registered image and updating your app with no downtime.

This is mostly intended for use with github actions and the github container registry, but the core implementation is workflow/registry agnostic.

## Requirements

1. A repository with automation that builds a new image on code changes. (See [Push your app to the GitHub Container Registry](#push-your-app-to-the-github-container-registry))

2. A Webhook that triggers when that new image is pushed to a registry. (See [Set up a webhook in your GitHub Repo](#set-up-a-webhook-in-your-github-repo))

3. A server that runs the image with Docker compose.

4. A docker-aware reverse-proxy such as [Traefik](https://doc.traefik.io/traefik/getting-started/install-traefik/), [Caddy](https://caddyserver.com/docs/quick-starts/reverse-proxy), or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) that can handle routing incoming traffic between containers as a new image is rolled out.

## Usage

### Volumes

`/app` is the `WORKINGDIR` of the image

**Required**

`/app/compose.yaml` - The compose file with your service definitions.

`/var/run/docker.sock` - The running Docker socket the container should attach to.

> [!CAUTION]
> Mounting the Docker socket as a volume [comes with security risks](https://docs.docker.com/engine/security/protect-access/), so it is recommended to [run Docker in Rootless mode](https://docs.docker.com/engine/security/rootless/) if possible. In rootless mode, the socket can typically be found at `/run/user/$UID/docker.sock`

**Optional**

`/var/scripts/` - A directory containing any custom hooks you would like to add

`/etc/webhook/config.yaml` - The configuration file for the webhook service

> The image comes with a preconfigured `gh-pkg-rollout.sh` hook and `config.yaml` to handle webhooks from GitHub automatically.
> See [Adding Custom Hooks](#adding-custom-hooks) for more information.

### Secrets & Env Vars

**Required** (if you are using the default `gh-pkg-rollout` hook and `config.yaml`)

| Type   | Name               | Description                                                           |
| ------ | ------------------ | --------------------------------------------------------------------- |
| ENV    | `APP_IMAGE`        | Docker image for your app (format: `ghcr.io/<username>/<repo>:<tag>`) |
| ENV    | `APP_SERVICE_NAME` | Which service to apply the rollout to                                 |
| SECRET | `WEBHOOK_SECRET`   | Secret used for verification of the webhook                           |

**Optional**

| Type   | Name                | Description                                                             |
| ------ | ------------------- | ----------------------------------------------------------------------- |
| ENV    | `REGISTRY_URL`      | Container registry URL (`ghcr.io`, for example) used for `docker login` |
| ENV    | `REGISTRY_USERNAME` | Username for the container registry                                     |
| ENV    | `WEBHOOK_PORT`      | Port the image listens on (default 9000)                                |
| SECRET | `REGISTRY_PASSWORD` | Password (or access token) for the container registry                   |

> [!IMPORTANT]
> Since `webhook-rollout` runs `docker compose` from within the container, it needs access to any env vars that are necessary for your web app and reverse proxy.
> For example, in the [Traefik example](#traefik-example) below, the `DOMAIN` is passed to the `webhook-rollout` service because the `webapp` service requires it for deployment.
>
> If you are using a `.env` file, you can mount it as a volume to handle such cases. (But that may also add some unnecessary exposure of your env vars)

### Configuring your compose file

#### Traefik Example

```yaml
# compose.yaml

secrets:
  REGISTRY_PASSWORD:
    environment: "REGISTRY_PASSWORD"
  WEBHOOK_SECRET:
    environment: "WEBHOOK_SECRET"

services:
  webapp:
    image: ${APP_IMAGE:-webapp:latest}
    environment:
      APP_PORT: ${APP_PORT:-3000}
    healthcheck:
      test: test ! -f /tmp/drain && curl -f http://localhost:${APP_PORT:-3000}/healthcheck
      interval: 10s
      timeout: 2s
      retries: 3
    labels:
      - traefik.enable=true
      - traefik.http.routers.webapp.entrypoints=web
      - traefik.http.routers.webapp.rule=Host(`${DOMAIN}`)
      - traefik.http.services.webapp.loadbalancer.server.port=${APP_PORT:-3000}
      # DRAIN CONTAINER ON ROLLOUT - https://docker-rollout.wowu.dev/container-draining.html
      - docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 45

  webhook-rollout:
    image: lotap/webhook-rollout
    environment:
      - APP_IMAGE=${APP_IMAGE}
      - APP_SERVICE_NAME=webapp
      - REGISTRY_URL=${REGISTRY_URL}
      - REGISTRY_USERNAME=${REGISTRY_USERNAME}
      - WEBHOOK_PORT=${WEBHOOK_PORT:-9000}
      - DOMAIN=${DOMAIN}
    secrets:
      - REGISTRY_PASSWORD
      - WEBHOOK_SECRET
    volumes:
      - ${CONTAINER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
      - ./compose.yaml:/app/compose.yaml:ro
    labels:
      - traefik.enable=true
      - traefik.http.routers.webhook.entrypoints=webhook
      - traefik.http.routers.webhook.rule=Host(`${DOMAIN:-localhost}`)
      - traefik.http.services.webhook.loadbalancer.server.port=${WEBHOOK_PORT:-9000}

  traefik:
    image: traefik
    command:
      # ENTRY
      - --entryPoints.web.address=:80
      - --entryPoints.webhook.address=:${WEBHOOK_PORT:-9000}
      # PROVIDER
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
    ports:
      - 80:80 # HTTP
      - ${WEBHOOK_PORT:-9000}:${WEBHOOK_PORT:-9000} # Webhook
    volumes:
      - ${CONTAINER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock:ro
```

##### SSL Certs

If you are using [Traefik](https://doc.traefik.io/traefik/getting-started/install-traefik/) to handle a cert, you will need to share access to it with the `webhook-rollout` service.

```yaml
webhook-rollout:
  # ...
  volumes:
    # ...
    - ./acme:/app/acme

traefik:
  # ...
  command:
    # ...
    - --certificatesresolvers.app-resolver.acme.storage=/acme/acme.json
  volumes:
    # ...
    - ./acme:/app/acme
```

### Adding Custom Hooks

webhook-rollout comes pre-configured with a single script that will work for most people. If you need additional functionality, you will need to update code in two places and mount them as volumes:

1. The actual script(s). Mounted to `/var/scripts/`

2. The configuration file. Mounted to `/etc/webhook/config.yaml`. This acts as a place to register the scripts and add rules for their execution. [Configuration details can be found in the webhook readme and docs](https://github.com/adnanh/webhook#configuration). You can find the default config for this project at `root/etc/webhook/config.yaml`. Note that this project expects the .yaml extension. You will need to provide a custom entry script to use .json. See `root/usr/local/bin/entrypoint.sh` for details.

> [!IMPORTANT]
> Any binaries you need for custom hooks will need to be installed or added to the Dockerfile by cloning/forking and building a custom image.

#### Example Custom Hook

```sh
#!/usr/bin/env sh
set -e

# install jq
if ! command -v jq > /dev/null 2>&1; then
    apk add --no-cache jq
fi

# grab data from an endpoint
RES=$(wget -qO- https://jsonplaceholder.typicode.com/posts/1)

# log the json data
echo "$RES" | jq .

exit 0
```

## GitHub Configuration

### Push your app to the GitHub Container Registry

Creating an image automatically is relatively simple to set up with a github action. You can see this project's action to do so at `.github/workflows/publish.yaml`

Here is a simple example for a generic web app that creates an image when a change to `apps/web` is made on the `trunk` branch:

```yaml
name: Build & Publish @/apps/web

on:
  push:
    branches: [trunk]
    paths: ["apps/web/**"]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}-web

concurrency:
  group: web
  cancel-in-progress: true

permissions:
  contents: read
  packages: write
  attestations: write
  id-token: write

jobs:
  build-and-push-image:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout your repository using git
        uses: actions/checkout@v5

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to the Container registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels) for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      - name: Build and push Docker image
        id: push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./apps/web/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

The code above is based on the [github documentation found here](https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions#publishing-a-package-using-an-action).

More information about the github container registry can be found [here](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

### Set up a webhook in your GitHub Repo

...(Docs coming soon)

### Get a Personal Access Token

...(Docs coming soon)

## Securing your webhook

It's recommended to limit connections to your webhook port to prevent malicious activity, much like you would for ssh. If you are using [ufw](https://help.ubuntu.com/community/UFW), you can run `ufw limit 9000/tcp`.
