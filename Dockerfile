FROM ubuntu:24.04

ARG RUNNER_VERSION="2.330.0"

# Prevents installdependencies.sh from prompting the user and blocking the image creation
ARG DEBIAN_FRONTEND=noninteractive

RUN useradd -m docker

COPY install_tools.sh /tmp/install_tools.sh
RUN chmod +x /tmp/install_tools.sh \
    && /tmp/install_tools.sh \
    && rm -rf /tmp/**

# add node to PATH
ENV PATH="$PATH:/usr/local/bin/node/bin"

# download the runner and install dependencies; keep tar.gz for later use
RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
    && curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && mkdir /tmp/runner-install \
    && tar xzf /home/docker/actions-runner/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -C /tmp/runner-install \
    && chown -R docker /home/docker /tmp/runner-install \
    && /tmp/runner-install/bin/installdependencies.sh \
    && rm -rf /tmp/runner-install

COPY start.sh start.sh
RUN chmod +x start.sh

# since the config and run script for actions are not allowed to be run by root,
# set the user to "docker" so all subsequent commands are run as the docker user
USER docker

ENTRYPOINT ["./start.sh"]
