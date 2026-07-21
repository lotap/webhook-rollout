ARG ALPINE_VERSION=3.24.1
FROM alpine:${ALPINE_VERSION}

ARG DOCKER_VERSION=29.5.3
ARG DOCKER_CLI_COMPOSE_VERSION=5.1.4
ARG WEBHOOK_VERSION=2.8.3
ARG TINI_VERSION=0.19.0

ARG DOCKER_ROLLOUT_RELEASE=v0.14

ARG WEBHOOK_PORT=9000
ENV WEBHOOK_PORT=$WEBHOOK_PORT

# Install packages with pinned versions
RUN --mount=type=cache,target=/var/cache/apk \
  apk add --no-cache \
  docker~=${DOCKER_VERSION} \
  docker-cli-compose~=${DOCKER_CLI_COMPOSE_VERSION} \
  webhook~=${WEBHOOK_VERSION} \
  tini~=${TINI_VERSION}

# Create necessary directories
RUN mkdir -p \
  /app \
  /etc/webhook \
  /var/log/webhook \
  /var/scripts \
  /root/.docker/cli-plugins

# Install docker-rollout https://github.com/wowu/docker-rollout
RUN wget -qO /root/.docker/cli-plugins/docker-rollout \
  https://raw.githubusercontent.com/wowu/docker-rollout/${DOCKER_ROLLOUT_RELEASE}/docker-rollout && \
  chmod 755 /root/.docker/cli-plugins/docker-rollout

# Copy default configuration file
COPY --link ./root/etc/webhook/config.yaml /etc/webhook/config.yaml

# Copy default script(s) to /tmp and make executable
# (The entrypoint script will move it to /var or delete it if the file already exists in the volume)
COPY --link --chmod=755 ./root/var/scripts/gh-pkg-rollout.sh /tmp/gh-pkg-rollout.sh

# Copy the entrypoint script and make it executable
COPY --link --chmod=755 ./root/usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /app

EXPOSE $WEBHOOK_PORT

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -nv -t1 -O /dev/null http://localhost:${WEBHOOK_PORT} || exit 1
