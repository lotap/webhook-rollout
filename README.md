# webhook-rollout
[webhook](https://github.com/adnanh/webhook) and [docker-rollout](https://github.com/wowu/docker-rollout), 2 great libraries that go great together! 

This repo creates a single image that packages them for convenience - providing you with a simple way to **deploy-on-push on any server with docker compose**

## Usage

### Configuring your compose file

This is intended to be used with a docker-aware reverse proxy like [Traefik](https://doc.traefik.io/traefik/getting-started/install-traefik/), [Caddy](https://caddyserver.com/docs/quick-starts/reverse-proxy), or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy).

You also will need to mount the Docker socket as a volume. [That comes with security risks](https://docs.docker.com/engine/security/protect-access/), so it is recommended to [run Docker in Rootless mode](https://docs.docker.com/engine/security/rootless/) if possible. In rootless mode, the socket can be found at `/run/user/$UID/docker.sock`

### Traefik Example

example `compose.yaml`

```yaml
secrets:
  GH_TOKEN:
    environment: "GH_TOKEN"
  WEBHOOK_SECRET:
    environment: "WEBHOOK_SECRET"

services:
  webapp:
    image: ${IMAGE:-webapp:latest}
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
    image: webhook-rollout
    environment:
      - GH_USERNAME=${GH_USERNAME}
      - ROLLOUT_SERVICE_NAME=webapp
    secrets:
      - GH_TOKEN
      - WEBHOOK_SECRET
    volumes:
      - ${CONTAINER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
      - ./webhook-rollout/scripts:/var/scripts/:ro
      - ./webhook-rollout/config.yaml:/etc/webhook/config.yaml:ro
      - ./compose.yaml:/app/compose.yaml:ro
    labels:
      - traefik.enable=true
      - traefik.http.routers.webhook.entrypoints=webhook
      - traefik.http.routers.webhook.rule=Host(`${DOMAIN:-localhost}`)
      - traefik.http.services.webhook.loadbalancer.server.port=9000

  traefik:
    image: traefik
    command:
      # ENTRY
      - --entryPoints.web.address=:80
      - --entryPoints.webhook.address=:9000
      # PROVIDER
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
    ports:
      - 80:80 # HTTP
      - 9000:9000 # Webhook
    volumes:
      - ${CONTAINER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock:ro

```
> [!NOTE]
> Do not use the above for an actual production `compose.yaml`. You should make sure to add ssl certs, necessary `restart` policy, `network` config, etc based on your needs

Assuming the above `compose.yaml`, you can use an `.env` file like this:
```
GH_USERNAME=#GitHub username
GH_TOKEN=#GitHub Personal Access Token
WEBHOOK_SECRET=#Secret used in the webhook
IMAGE=#Docker image for your webapp (format: ghcr.io/<username>/<repo>:<tag>)
CONTAINER_SOCKET=#The docker socket to connect to (/run/user/<uid>/docker.sock in docker rootless)
DOMAIN=#Full domain name for the web application (format: www.example.com)
```

### GitHub 

#### Pushing your app to the GitHub Package Repository

...(Docs coming soon)

#### Setting up the webhook in your GitHub Repo

...(Docs coming soon)

