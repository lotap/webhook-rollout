# webhook-rollout

[![GitHub Release](https://img.shields.io/github/v/release/lotap/webhook-rollout?display_name=tag)](https://github.com/lotap/webhook-rollout/releases) [![Docker Image Version](https://img.shields.io/docker/v/lotap/webhook-rollout?logo=docker&logoColor=white&color=2496ED)](https://hub.docker.com/r/lotap/webhook-rollout)
[![Dependabot Updates](https://github.com/lotap/webhook-rollout/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/lotap/webhook-rollout/actions/workflows/dependabot/dependabot-updates) [![semantic-release: conventionalcommits](https://img.shields.io/badge/semantic--release-conventionalcommits-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)

[webhook](https://github.com/adnanh/webhook) and [docker-rollout](https://github.com/wowu/docker-rollout), 2 great libraries that go great together!

A simple way to **push-to-deploy on any server with docker compose**

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
> For example, in the [Traefik example](#traefik-example) below, the `DOMAIN` is passed to the `webhook-rollout` service because the `webapp` service requires it for .
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
      - traefik.http.routers.webapp.entrypoints=websecure
      - traefik.http.routers.webapp.rule=Host(`${DOMAIN:-localhost}`)
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
      - 9000:9000 # Webhook
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
    - ./acme:/acme
```

### Adding Custom Hooks

...(Docs coming soon)

> [!IMPORTANT]
> Any binaries you need for custom hooks will need to be added by cloning/forking and building a custom image.

## GitHub Configuration

### Push your app to the GitHub Container Registry

...(Docs coming soon)

### Set up a webhook in your GitHub Repo

...(Docs coming soon)

### Get a Personal Access Token

...(Docs coming soon)
