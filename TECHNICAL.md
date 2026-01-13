
# Architecture and Design Notes

This document describes how the Docker-based GitHub Actions runner is structured internally and why certain design decisions were made.

---

## GitHub Actions runner installation

The official [GitHub Actions runner](https://github.com/actions/runner/releases/tag/v2.331.0) is downloaded as a **tarball** during image build.

The tarball is:
- Extracted into a temporary location
- System dependencies installed via [`installdependencies.sh`](https://github.com/actions/runner/blob/v2.331.0/src/Misc/layoutbin/installdependencies.sh)
- Temporary extracted files cleaned up afterward to reduce image size

The runner tarball itself is intentionally kept in the image as `runner.tar.gz` so new runner instances can be created later without re-downloading.

---

## Node.js strategy

#### Why Node is needed at all

Many GitHub Actions are **JavaScript-based actions**, including:
- [`actions/checkout`](https://github.com/actions/checkout/blob/v6/action.yml#L107)
- [`actions/setup-node`](https://github.com/actions/setup-node/blob/v6/action.yml#L40)
- Many marketplace actions

These actions do not use the system Node runtime. They rely on the [Node](https://github.com/actions/runner/blob/v2.331.0/docs/checks/nodejs.md) [runtime](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax#runsusing-for-javascript-actions) [bundled](https://github.com/actions/runner/blob/v2.331.0/src/Misc/externals.sh) with the GitHub Actions runner (under `externals/`).

> Alpine versions are [removed](https://github.com/jurakovic/github-runner-dockerfile/blob/update/start.sh#L163) to save ~300 MB of image size because this image only runs on Ubuntu.

#### System Node

System Node is installed (via [`install_tools.sh`](https://github.com/jurakovic/github-runner-dockerfile/blob/update/install_tools.sh#L23-L27)) for workflows that call `node` directly (scripts/tools), not for JavaScript marketplace actions.

Node is installed under `/usr/local/lib/nodejs` and [added](https://github.com/jurakovic/github-runner-dockerfile/blob/update/Dockerfile#L16-L17) to `PATH` in the Dockerfile.

---

## Runner layout

- Base directory: `/home/runner/actions-runner`
- Central log: `/home/runner/actions-runner/runners.log`
- Each runner has its own subdirectory:
  - `/home/runner/actions-runner/runner-1`
  - `/home/runner/actions-runner/runner-2`
  - etc.

Each runner directory includes its own log file:

- `/home/runner/actions-runner/<runner-name>/runner.log`

---

## Runner lifecycle

### Container start (supervisor mode)

When the container starts (PID 1), `start.sh` runs in supervisor mode:

- Ensures the central log exists
- Tails the central log
- Finds existing runner directories containing `run.sh` and starts them

If no runners exist, the container stays idle.

### Runner creation

When you `docker exec` into the container to add a runner:

- A short-lived runner registration token is requested from the GitHub API using `TOKEN` (PAT or GitHub App token)
- A new runner directory is created under `/home/runner/actions-runner/<name>`
- The runner tarball (`runner.tar.gz`) is extracted into that directory
- The runner is configured with `config.sh --disableupdate`
- The runner is started with `run.sh`

### Runner removal

When you remove a runner:

- A short-lived removal token is requested from the GitHub API
- `config.sh remove` is executed
- The runner directory is deleted

#### Repository inference during removal

If `--repo` / `REPO` is not provided during removal, the script attempts to infer the repository from:

- `/home/runner/actions-runner/<runner-name>/.runner`

by reading the `gitHubUrl` field and converting it to `owner/repo`.

---

## Secrets and security notes

This setup uses **environment variables** for passing secrets (e.g. `TOKEN`).

Important notes:

- Environment variables are visible via `docker inspect`, `docker exec env`, and `/proc`
- Anyone with Docker access already has root-equivalent access

This is considered acceptable for:
- Personal servers
- Single-user machines
- Dedicated CI hosts

For stronger isolation, a different architecture is required.
