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
    python3 python3-venv python3-dev python3-pip \
    wget

# Install Node.js
NODE_VERSION="24.13.0"
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" \
    && curl -s "${NODE_DOWNLOAD_URL}" -L -o /tmp/node.tar.gz \
    && tar -xzf /tmp/node.tar.gz -C /tmp \
    && mv "/tmp/node-v${NODE_VERSION}-linux-x64" /usr/local/lib/nodejs

# Install yq
YQ_VERSION="4.50.1"
YQ_DOWNLOAD_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" \
    && curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz \
    && tar -xzf /tmp/yq.tar.gz -C /tmp \
    && mv "/tmp/yq_linux_amd64" /usr/local/bin/yq
