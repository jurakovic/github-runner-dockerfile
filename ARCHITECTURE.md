
# Architecture and Design Notes

This document describes how the Docker-based GitHub Actions runner is structured internally and why certain design decisions were made.

---

## GitHub Actions runner installation

The official GitHub Actions runner is downloaded as a **tarball** during build.

Example:
- `actions-runner-linux-x64-<version>.tar.gz`

The tarball is:
- Extracted into a temporary location
- System dependencies installed via `installdependencies.sh`
- Cleaned up afterward to reduce image size

---

## Node.js strategy

### Why Node is needed at all

Many GitHub Actions are **JavaScript-based actions**, including:
- `actions/checkout`
- `actions/setup-node`
- Many marketplace actions

These actions **do not use system Node**.  
They rely on the Node runtime **bundled with the GitHub Actions runner**.

### Bundled Node versions

The runner tarball includes multiple Node distributions under `externals/`:

- `node20`
- `node20_alpine`
- `node24`
- `node24_alpine`

These exist to support:
- Different base OS environments
- Backward compatibility
- Alpine-based runners

#### Why Alpine variants are removed

This image:
- Runs only on Ubuntu
- Never executes in Alpine or musl environments

Therefore:
- `node20_alpine`
- `node24_alpine`

are safely removed to save ~300 MB of image size.

---

### Why system Node is not used

Although Node can be installed via `apt` or downloaded manually as in this image, it is intentionally **not relied upon**:

- GitHub Actions explicitly uses bundled Node
- JS actions expect a known, pinned Node runtime
- Mixing system Node with runner Node can cause subtle failures

---

## Runner layout

- Base directory: `/home/docker/actions-runner`
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

This setup uses **environment variables** for passing secrets (e.g. runner registration tokens).

Important notes:

* Environment variables are visible via `docker inspect`, `docker exec env`, and `/proc`
* This is **normal and expected behavior**
* Anyone with Docker access already has root-equivalent access

This is considered acceptable for:

* Personal servers
* Single-user machines
* Dedicated CI hosts

For stronger isolation, a different architecture is required.
