# Docker Build Helpers

This directory contains the local Podman build helpers used to build ClickHouse from source on macOS with a Podman machine.

## Files

- `build-clickhouse-image.sh`
  - Runs the in-container ClickHouse build.
  - Avoids Podman issues with complex inline shell in the `Dockerfile`.
- `podman-build-local.sh`
  - Builds the current checkout with `podman build`.
  - Repairs broken local submodule worktrees before starting the image build.
  - Passes image metadata into the Docker build through `IMAGE_SOURCE`, `IMAGE_REVISION`, and `IMAGE_CREATED`.
- `podman-build-machine.sh`
  - Stages the source tree inside the Podman VM and builds from there.
  - This is the preferred entrypoint on macOS because it avoids large remote-context copy failures and xattr issues from mounted host paths.

## Prerequisites

- Podman machine is installed and running.
- The local checkout has initialized submodules if you are building the current working tree.
- Enough disk space in the Podman VM for an additional staged source tree.

Check Podman status:

```bash
podman version
podman machine list
```

## Recommended Build Command

Build the current local checkout:

```bash
cd /<PATH/ClickHouse
BUILD_JOBS=1 ./docker/podman-build-machine.sh
```

This stages the repo into `/var/tmp/clickhouse-build-context` inside the Podman VM and runs the image build there.

## Build a Specific Repo and Version

You can build a different repo or a different revision without manually cloning it first.

Build from GitHub `owner/repo` notation:

```bash
./docker/podman-build-machine.sh \
  --repo ClickHouse/ClickHouse \
  --version v26.2.1.1 \
  --name clickhouse-26.2.1.1
```

Build from a full git URL:

```bash
./docker/podman-build-machine.sh \
  --repo-url https://github.com/ClickHouse/ClickHouse.git \
  --version master \
  --name clickhouse-master
```

Notes:

- `--repo` accepts either `owner/repo` or a full git URL.
- `--version` accepts a branch, tag, or commit.
- `--name` sets the output image tag.
- When `--repo` or `--repo-url` is used, the script clones the requested source inside the Podman VM, initializes submodules, overlays the local Docker helper files, and then builds.

## Useful Environment Variables

You can use environment variables instead of CLI flags:

```bash
IMAGE_TAG=clickhouse-dev \
REPO=ClickHouse/ClickHouse \
REPO_VERSION=v26.2.1.1 \
BUILD_JOBS=1 \
./docker/podman-build-machine.sh
```

Supported variables:

- `IMAGE_TAG`
- `REPO`
- `REPO_URL`
- `REPO_VERSION`
- `BUILD_JOBS`
- `BUILD_FORMAT`
- `REMOTE_REPO_DIR`
- `IMAGE_SOURCE`
- `IMAGE_REVISION`
- `IMAGE_CREATED`

## Direct Local Build

If you want to build directly from the current checkout instead of using VM staging:

```bash
./docker/podman-build-local.sh .
```

This can still fail on macOS-mounted paths for very large contexts. Use `podman-build-machine.sh` when possible.

## Known Behavior

- The helper scripts intentionally exclude the root `.git` directory from the Docker build context.
- The image metadata labels are populated from the selected repo URL and revision when available.
- The machine build script copies the local Docker helper files into the staged or cloned repo so the build uses the same patched Docker flow.
