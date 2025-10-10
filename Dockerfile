FROM ubuntu:24.04

ARG RUNNER_VERSION="2.328.0"

# Prevents installdependencies.sh from prompting the user and blocking the image creation
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update -y && apt upgrade -y && useradd -m docker
RUN apt install -y --no-install-recommends \
    curl jq build-essential libssl-dev libffi-dev libicu-dev python3 python3-venv python3-dev python3-pip git unzip libasound2t64 pulseaudio \
    inetutils-ping wget nodejs

RUN YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq ".assets[] | select(.name == \"yq_linux_amd64.tar.gz\")" \
      | jq -r '.browser_download_url') \
    && curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz \
    && tar -xzf /tmp/yq.tar.gz -C /tmp \
    && mv "/tmp/yq_linux_amd64" /usr/local/bin/yq

# download the runner archive but do not extract it into a dynamic directory
RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
    && curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# extract to a temporary directory to run installdependencies.sh
RUN mkdir /tmp/runner-install \
    && tar xzf /home/docker/actions-runner/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -C /tmp/runner-install \
    && chown -R docker /home/docker /tmp/runner-install \
    && /tmp/runner-install/bin/installdependencies.sh \
    && rm -rf /tmp/runner-install

COPY start.sh start.sh

# make the script executable
RUN chmod +x start.sh

# since the config and run script for actions are not allowed to be run by root,
# set the user to "docker" so all subsequent commands are run as the docker user
USER docker

ENTRYPOINT ["./start.sh"]
