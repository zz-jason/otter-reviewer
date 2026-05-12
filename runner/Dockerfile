FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODEX_VERSION=latest

RUN sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|http://cn.archive.ubuntu.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|http://cn.archive.ubuntu.com/ubuntu|g' \
    /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        nodejs \
        npm \
        tar \
        unzip \
    && npm install -g "@openai/codex@${CODEX_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash runner \
    && mkdir -p /home/runner/.codex /home/runner/actions-runner /home/runner/_work \
    && chown -R runner:runner /home/runner

COPY runner/entrypoint.sh /usr/local/bin/otter-runner-entrypoint
RUN chmod +x /usr/local/bin/otter-runner-entrypoint

USER runner
WORKDIR /home/runner

ENV CODEX_HOME=/home/runner/.codex
ENV RUNNER_WORKDIR=/home/runner/_work

ENTRYPOINT ["/usr/local/bin/otter-runner-entrypoint"]
