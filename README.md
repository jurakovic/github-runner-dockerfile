
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

- The container starts and waits idle
- Runners are registered dynamically using [`start.sh`](start.sh)
- Each runner lives in its own directory under the Actions runner base path
- GitHub Actions runner binaries are downloaded as a tarball during image build

For deeper technical details, see [Architecture.md](Architecture.md).

---

## Running the container

#### Start an empty runner container

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

#### Add a runner

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  github-runner ./start.sh \
  --name 'runner-1' \
  --repo 'owner/repo'
```

* `TOKEN` is a GitHub Personal Access Token (PAT) / GitHub App token used to request a short-lived runner registration token via the [GitHub API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-a-repository--fine-grained-access-tokens)
* `--name` is the runner name shown in GitHub
* `--repo` is the repository to register the runner with

> The fine-grained token must have the following permission set:  
> "Administration" repository permissions (write)

---

### Remove a runner

```bash
docker exec -d \
  -e TOKEN='<PAT>' \
  github-runner ./start.sh \
  --remove 'runner-1' \
  --repo 'owner/repo'
```

This:

* Unregisters the runner from GitHub
* Removes its local files

---

## Debugging and inspection

#### Container logs

```bash
docker logs github-runner -n 200
```

#### Runner-specific logs

Each runner maintains its own log file.

```bash
docker exec -it github-runner cat /home/docker/actions-runner/runner-1/runner.log
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
