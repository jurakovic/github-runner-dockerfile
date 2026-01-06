
# GitHub Actions Runner (Docker)

This repository contains a **Docker image for a self-hosted GitHub Actions runner**.

> It is primarily built for my personal use, tailored to my workflows, tooling preferences, and infrastructure.  
> That said, anyone is welcome to fork or clone this repository and adapt it to their own needs.

The image is designed to:
- Run one or more GitHub Actions runners inside a single container
- Be reusable across repositories
- Stay running as a “runner host”, with runners added or removed dynamically
- Avoid unnecessary dependencies and keep behavior explicit and debuggable

---

## What this image is (and is not)

### This image is
- A long-running container that hosts GitHub Actions runners
- Intended for **self-hosted runners**
- Managed via `docker run` + `docker exec`
- Suitable for personal servers, homelabs, or dedicated CI machines

### This image is not
- A drop-in replacement for GitHub-hosted runners
- A multi-tenant or hardened environment
- Optimized for running untrusted workloads

---

## How it works (high level)

- The container starts and waits idle
- Runners are registered dynamically using `start.sh`
- Each runner lives in its own directory under the Actions runner base path
- GitHub Actions runner binaries are downloaded as a tarball during image build
- Node.js is provided by the runner bundle (Node 24), not by the OS

For deeper technical details, see **Architecture.md**.

---

## Running the container

### Start an empty runner container

```bash
docker run -d \
  --name github-runner \
  --restart always \
  ghcr.io/jurakovic/github-runner-dockerfile:2026-01-05.2
```

This starts a container **without any registered runners**.

---

## Managing runners

All runner management is done via `docker exec` and `start.sh`.

### Add a runner

```bash
docker exec -d \
  -e TOKEN='<TOKEN>' \
  github-runner ./start.sh \
  --name 'runner-1' \
  --repo 'owner/repo'
```

* `TOKEN` is a **GitHub runner registration token**
* `--name` is the runner name shown in GitHub
* `--repo` can be a repository or organization

---

### Remove a runner

```bash
docker exec -d \
  -e TOKEN='<TOKEN>' \
  github-runner ./start.sh \
  --remove 'runner-1' \
  --repo 'owner/repo'
```

This:

* Unregisters the runner from GitHub
* Removes its local files

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

If you require stronger isolation, Docker alone is not sufficient.

---

## Debugging and inspection

### Container logs

```bash
docker logs github-runner -n 200
```

### Runner-specific logs

Each runner maintains its own log file.

```bash
docker exec -it github-runner \
  cat /home/docker/actions-runner/runner-1/runner.log
```

### Runtime inspection

```bash
docker exec -it github-runner printenv
docker exec -it github-runner ps -eo pid,ppid,cmd --forest
```

---

## Customization

This image is intentionally opinionated but easy to modify.

You may want to customize:

* Installed system tools (`install_tools.sh`)
* Node.js handling
* Runner registration logic
* Cleanup or lifecycle behavior

Forking this repository is encouraged if your needs differ.
