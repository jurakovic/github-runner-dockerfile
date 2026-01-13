FROM ubuntu:24.04

ARG RUNNER_VERSION="2.331.0"

# Prevents installdependencies.sh from prompting the user and blocking the image creation
ARG DEBIAN_FRONTEND=noninteractive

RUN useradd -m runner

COPY install_tools.sh /tmp/install_tools.sh
RUN chmod +x /tmp/install_tools.sh \
    && /tmp/install_tools.sh \
    && rm -rf /tmp/* \
    && rm -rf /var/lib/apt/lists/*

# add node to PATH
ENV PATH="$PATH:/usr/local/lib/nodejs/bin"

# download the runner and install dependencies; keep tar.gz for later use
RUN cd /home/runner && mkdir actions-runner && cd actions-runner \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && mkdir /tmp/runner-install \
    && tar xzf /home/runner/actions-runner/runner.tar.gz -C /tmp/runner-install \
    && chown -R runner /home/runner /tmp/runner-install \
    && /tmp/runner-install/bin/installdependencies.sh \
    && rm -rf /tmp/runner-install \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh start.sh
RUN chmod +x start.sh

# since the config and run script for actions are not allowed to be run by root,
# set the user to "runner" so all subsequent commands are run as the runner user
USER runner

ENTRYPOINT ["./start.sh"]
