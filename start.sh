#!/bin/bash

REPOSITORY=$REPO
ACCESS_TOKEN=$TOKEN
WORKER_NAME="${NAME:-$HOSTNAME}"

echo "REPO: ${REPOSITORY}"
echo "ACCESS_TOKEN: ${ACCESS_TOKEN}"
echo "WORKER_NAME: ${WORKER_NAME}"

REG_TOKEN=$(curl -sS -X POST -H "Authorization: token ${ACCESS_TOKEN}" -H "Accept: application/vnd.github+json" https://api.github.com/repos/${REPOSITORY}/actions/runners/registration-token | jq .token --raw-output)

cd /home/docker/actions-runner

mkdir ${WORKER_NAME} && tar xzf ./actions-runner-linux-x64-*.tar.gz -C ./${WORKER_NAME}

cd ./${WORKER_NAME}

./config.sh --name ${WORKER_NAME} --url https://github.com/${REPOSITORY} --token ${REG_TOKEN}

cleanup() {
    echo "Removing runner..."
    ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
