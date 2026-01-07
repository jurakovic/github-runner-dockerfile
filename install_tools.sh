#!/usr/bin/env bash
set -euo pipefail

apt update -y
apt upgrade -y

apt install -y --no-install-recommends \
    curl \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    libicu-dev \
    git \
    unzip \
    libasound2t64 \
    pulseaudio \
    inetutils-ping \
    wget \
    python3 python3-venv python3-dev python3-pip

# Install Node.js 24
NODE_VERSION="24.12.0"
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" \
    && curl -s "${NODE_DOWNLOAD_URL}" -L -o /tmp/node.tar.gz \
    && tar -xzf /tmp/node.tar.gz -C /tmp \
    && mv "/tmp/node-v${NODE_VERSION}-linux-x64" /usr/local/bin/node

# Install yq
YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq ".assets[] | select(.name == \"yq_linux_amd64.tar.gz\")" \
      | jq -r '.browser_download_url') \
    && curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz \
    && tar -xzf /tmp/yq.tar.gz -C /tmp \
    && mv "/tmp/yq_linux_amd64" /usr/local/bin/yq
