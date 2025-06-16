ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG DOCKER_VERSION=~28.2
ARG DOCKER_CLI_COMPOSE_VERSION=~2.36
ARG WEBHOOK_VERSION=~2.8
ARG CURL_VERSION=~8.14

ARG DOCKER_ROLLOUT_TAG=v0.12

# Install packages with pinned versions
RUN apk update && apk add --no-cache \
  docker=${DOCKER_VERSION} \
  docker-cli-compose=${DOCKER_CLI_COMPOSE_VERSION} \
  webhook=${WEBHOOK_VERSION} \
  curl=${CURL_VERSION}

# Create necessary directories
RUN mkdir -p \
  /app \
  /etc/webhook \
  /var/log/webhook \
  /var/scripts \
  ~/.docker/cli-plugins

# Install docker-rollout https://github.com/wowu/docker-rollout
# Download and extract tar from GitHub
RUN curl -#L -o /tmp/docker-rollout.tar.gz https://api.github.com/repos/wowu/docker-rollout/tarball/${DOCKER_ROLLOUT_TAG} && \
  tar -xzf /tmp/docker-rollout.tar.gz -C /tmp/
# Move docker-rollout script to Docker cli plugins directory
RUN  mv /tmp/wowu-docker-rollout-*/docker-rollout ~/.docker/cli-plugins/
# Cleanup excess files
RUN  rm -rf /tmp/docker-rollout.tar.gz /tmp/wowu-docker-rollout-*
# Make the script executable
RUN chmod +x ~/.docker/cli-plugins/docker-rollout

# Copy the start script and make it executable
COPY ./usr/loccal/bin/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/loccal/bin/start.sh

WORKDIR /app

EXPOSE 9000

ENTRYPOINT ["/usr/loccal/bin/start.sh"]
