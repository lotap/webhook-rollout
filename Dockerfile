ARG ALPINE_VERSION=3.24.1
FROM alpine:${ALPINE_VERSION}

ARG DOCKER_VERSION=29.5.3
ARG DOCKER_CLI_COMPOSE_VERSION=5.1.4
ARG WEBHOOK_VERSION=2.8.3
ARG CURL_VERSION=8.21.0
ARG TINI_VERSION=0.19.0

ARG DOCKER_ROLLOUT_RELEASE=v0.14

ARG WEBHOOK_PORT=9000
ENV WEBHOOK_PORT=$WEBHOOK_PORT

# Install packages with pinned versions
RUN apk add --no-cache \
  docker~=${DOCKER_VERSION} \
  docker-cli-compose~=${DOCKER_CLI_COMPOSE_VERSION} \
  webhook~=${WEBHOOK_VERSION} \
  curl~=${CURL_VERSION} \
  tini~=${TINI_VERSION}

# Create necessary directories
RUN mkdir -p \
  /app \
  /etc/webhook \
  /var/log/webhook \
  /var/scripts \
  /root/.docker/cli-plugins

# Install docker-rollout https://github.com/wowu/docker-rollout
# Download and extract tar from GitHub
RUN curl -#L -o /tmp/docker-rollout.tar.gz https://api.github.com/repos/wowu/docker-rollout/tarball/${DOCKER_ROLLOUT_RELEASE} \
  && tar -xzf /tmp/docker-rollout.tar.gz -C /tmp/ \
  # Move docker-rollout script to Docker cli plugins directory
  && mv /tmp/wowu-docker-rollout-*/docker-rollout /root/.docker/cli-plugins/ \
  # Cleanup excess files
  && rm -rf /tmp/docker-rollout.tar.gz /tmp/wowu-docker-rollout-* \
  # Make the script executable
  && chmod +x /root/.docker/cli-plugins/docker-rollout

# Copy default configuration file
COPY ./root/etc/webhook/config.yaml /etc/webhook/config.yaml

# Copy default script(s) to /tmp and make executable
COPY --chmod=755 ./root/var/scripts/gh-pkg-rollout.sh /tmp/gh-pkg-rollout.sh

# Copy the entrypoint script and make it executable
COPY --chmod=755 ./root/usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /app

EXPOSE $WEBHOOK_PORT

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=5s \
  CMD curl -f http://localhost:${WEBHOOK_PORT} || exit 1
