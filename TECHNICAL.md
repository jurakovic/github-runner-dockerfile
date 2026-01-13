
# Architecture and Design Notes

This document describes how the Docker-based GitHub Actions runner is structured internally and why certain design decisions were made.

---

## GitHub Actions runner installation

The official [GitHub Actions runner](https://github.com/actions/runner/releases/tag/v2.331.0) is downloaded as a **tarball** during build.

The tarball is:
- Extracted into a temporary location
- System dependencies installed via [`installdependencies.sh`](https://github.com/actions/runner/blob/v2.331.0/src/Misc/layoutbin/installdependencies.sh)
- Extracted files cleaned up afterward to reduce image size

---

## Node.js strategy

#### Why Node is needed at all

Many GitHub Actions are **JavaScript-based actions**, including:
- [`actions/checkout`](https://github.com/actions/checkout/blob/v6/action.yml#L107)
- [`actions/setup-node`](https://github.com/actions/setup-node/blob/v6/action.yml#L40)
- Many marketplace actions

These actions **do not use system Node**. They rely on the [Node](https://github.com/actions/runner/blob/v2.331.0/docs/checks/nodejs.md) [runtime](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax#runsusing-for-javascript-actions) [bundled](https://github.com/actions/runner/blob/v2.331.0/src/Misc/externals.sh) with the GitHub Actions runner.

> Alpine variants are [removed](https://github.com/jurakovic/github-runner-dockerfile/blob/update/start.sh#L163) to save ~300 MB of image size because this image only runs on Ubuntu.

#### System Node

System Node is [installed](https://github.com/jurakovic/github-runner-dockerfile/blob/update/install_tools.sh#L23-L27) for workflows that call [`node`](https://github.com/jurakovic/github-runner-dockerfile/blob/update/Dockerfile#L16-L17) directly (scripts/tools), not for JS marketplace actions.

---

## Runner layout

- Base directory: `/home/runner/actions-runner`
- Each runner has its own subdirectory:
  - `runner-1`
  - `runner-2`
  - etc.

This allows:
- Multiple runners per container
- Independent logs
- Independent registration and removal

---

## Runner lifecycle

- Container starts and waits
- Runners are added dynamically using `start.sh`
- Registration tokens are provided at runtime
- Runners can be removed without restarting the container

This avoids:
- Rebuilding images per runner
- Baking secrets into images
- Container restarts for routine operations

---

## Secrets and security notes

This setup uses **environment variables** for passing secrets (e.g. PAT).

Important notes:

* Environment variables are visible via `docker inspect`, `docker exec env`, and `/proc`
* This is **normal and expected behavior**
* Anyone with Docker access already has root-equivalent access

This is considered acceptable for:

* Personal servers
* Single-user machines
* Dedicated CI hosts

For stronger isolation, a different architecture is required.
