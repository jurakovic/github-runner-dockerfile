
# GitHub Actions Runner (Docker)

This repository contains a **Docker image for a self-hosted GitHub Actions runner**.

The image is designed to:
- Run one or more GitHub Actions runners inside a single container
- Be reusable across repositories
- Stay running as a "runner host", with runners added or removed dynamically
- Avoid unnecessary dependencies and keep behavior explicit and debuggable

> It is primarily built for my personal use, tailored to my workflows, tooling preferences, and infrastructure.  
> That said, anyone is welcome to fork or clone this repository and adapt it to their own needs.

---

## What this image is (and is not)

#### This image is
- A long-running container that hosts GitHub Actions runners
- Intended for **self-hosted runners**
- Managed via `docker run` + `docker exec`
- Suitable for personal servers, homelabs, or dedicated CI machines

#### This image is not
- A drop-in replacement for GitHub-hosted runners
- A multi-tenant or hardened environment
- Optimized for running untrusted workloads

---

## How it works (high level)

- The container starts and waits idle (supervisor mode)
- Runners are registered dynamically using [`start.sh`](start.sh)
- Each runner lives in its own directory under the Actions runner base path:
  - `/home/runner/actions-runner/<runner-name>/`

For deeper technical details, see [TECHNICAL.md](TECHNICAL.md).

---

## Running the container

#### Start an empty runner container

```bash
docker run -d \
  --name github-runner \
  --restart always \
  -v "${PWD}/github-runner:/home/runner/actions-runner" \
  ghcr.io/jurakovic/github-runner-dockerfile:2026-01-05.2
```

This starts a container **without any registered runners**.

#### Persistence note

Mounting a volume to `/home/runner/actions-runner` is recommended:

- It keeps runner directories and configuration across container recreation
- Existing runners can be restarted automatically by the supervisor on container restart

Without a volume, deleting/recreating the container will remove local runner directories, while GitHub may still show the runners as registered but offline until removed.

---

## Managing runners

All runner management is done via `docker exec` and `start.sh`.

### Token requirements

The script requires a token that can call [GitHub's REST API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-a-repository--fine-grained-access-tokens) endpoint:

- `POST /repos/{owner}/{repo}/actions/runners/registration-token`

So `TOKEN` must be one of:
- a **GitHub Personal Access Token (PAT)** (classic or fine-grained), or
- a **GitHub App installation token**

> Fine-grained PAT note: the token must have repository permission:  
> **Administration (write)**

`TOKEN` must be passed via environment variable (do not put tokens on the command line).

---

### Environment variables

- `TOKEN` (required): PAT / GitHub App token used to request short-lived runner registration tokens
- `REPO` (optional): `owner/repo` (can also be provided via `--repo`)
- `NAME` (optional): runner name (can also be provided via `--name`)

---

#### Add a runner

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  github-runner ./start.sh \
  --name 'runner-1' \
  --repo 'owner/repo'
```

* `--name` is the runner name shown in GitHub
* `--repo` is the repository to register the runner with

You can also use environment variables:

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  -e NAME='runner-1' \
  -e REPO='owner/repo' \
  github-runner ./start.sh
```

---

### Remove a runner

#### Remove by passing the runner name explicitly

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  github-runner ./start.sh \
  --remove 'runner-1' \
  --repo 'owner/repo'
```

#### Remove using NAME + inferred repo (no `--repo` needed)

If `--repo` / `REPO` is not provided, the script will attempt to infer the repository from `/home/runner/actions-runner/<runner-name>/.runner`

Example:

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  -e NAME='runner-1' \
  github-runner ./start.sh --remove
```

This:
- Unregisters the runner from GitHub
- Removes its local files

---

### Build from source

```bash
git clone https://github.com/jurakovic/github-runner-dockerfile.git
cd github-runner-dockerfile

docker build -t github-runner:latest .

docker run -d \
  --name github-runner \
  --restart always \
  -v "${PWD}/github-runner:/home/runner/actions-runner" \
  github-runner:latest
```

---

## Debugging and inspection

#### Container logs

```bash
docker logs github-runner -n 200
```

#### Runner-specific logs

Each runner maintains its own log file.

```bash
docker exec -it github-runner cat /home/runner/actions-runner/runner-1/runner.log
```

#### Runtime inspection

```bash
docker exec -it github-runner printenv
docker exec -it github-runner ps -eo pid,ppid,cmd --forest
```

---

## Credits

todo

---

## References

todo
