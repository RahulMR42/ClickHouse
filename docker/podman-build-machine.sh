#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

remote_repo_dir="${REMOTE_REPO_DIR:-/var/tmp/clickhouse-build-context}"
image_tag="${IMAGE_TAG:-clickhouse-oci-local}"
build_jobs="${BUILD_JOBS:-1}"
build_format="${BUILD_FORMAT:-docker}"
repo_selector="${REPO:-${REPO_URL:-}}"
repo_version="${REPO_VERSION:-}"

usage() {
    cat <<'EOF'
Usage:
  ./docker/podman-build-machine.sh [options]

Options:
  --name, --image-tag TAG     Image tag to build. Default: clickhouse-oci-local
  --repo VALUE                Source repo to build. Accepts:
                              - owner/repo
                              - https://...git
                              - git@... / ssh://...
  --repo-url URL              Same as --repo, but explicit.
  --version REF               Git branch, tag, or commit to check out.
  --build-jobs N              Build jobs passed into the container build. Default: 1
  --build-format FORMAT       Podman build format. Default: docker
  --remote-dir DIR            Staging directory inside the Podman VM.
  --help                      Show this message.

Behavior:
  - Without --repo/--repo-url, the script stages the current checkout into the Podman VM
    and builds that snapshot.
  - With --repo or --repo-url, the script clones that repo inside the Podman VM,
    optionally checks out --version, overlays the local Docker build helpers, and builds it.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name|--image-tag)
            image_tag="$2"
            shift 2
            ;;
        --repo)
            repo_selector="$2"
            shift 2
            ;;
        --repo-url)
            repo_selector="$2"
            shift 2
            ;;
        --version|--ref)
            repo_version="$2"
            shift 2
            ;;
        --build-jobs)
            build_jobs="$2"
            shift 2
            ;;
        --build-format)
            build_format="$2"
            shift 2
            ;;
        --remote-dir)
            remote_repo_dir="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

resolve_repo_url() {
    local value="$1"

    if [[ -z "${value}" ]]; then
        return 0
    fi

    if [[ "${value}" == *"://"* || "${value}" == git@* || "${value}" == ssh://* ]]; then
        printf '%s\n' "${value}"
        return 0
    fi

    if [[ "${value}" == */* ]]; then
        printf 'https://github.com/%s.git\n' "${value}"
        return 0
    fi

    echo "Repo selector must be owner/repo or a full git URL: ${value}" >&2
    exit 1
}

resolved_repo_url="$(resolve_repo_url "${repo_selector}")"
local_repo_url="$(git -C "${repo_root}" remote get-url origin 2>/dev/null || true)"
image_source="${IMAGE_SOURCE:-${resolved_repo_url:-${local_repo_url}}}"
image_revision="${IMAGE_REVISION:-${repo_version}}"
image_created="${IMAGE_CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

overlay_build_assets_cmd=$(
    cat <<EOF
set -euo pipefail
mkdir -p '${remote_repo_dir}/docker'
cp '${repo_root}/Dockerfile' '${remote_repo_dir}/Dockerfile'
cp '${repo_root}/.dockerignore' '${remote_repo_dir}/.dockerignore'
install -m 755 '${repo_root}/docker/build-clickhouse-image.sh' '${remote_repo_dir}/docker/build-clickhouse-image.sh'
install -m 755 '${repo_root}/docker/podman-build-local.sh' '${remote_repo_dir}/docker/podman-build-local.sh'
if [[ -d '${remote_repo_dir}/contrib/thrift-cmake' ]]; then
  install -m 644 '${repo_root}/contrib/thrift-cmake/CMakeLists.txt' '${remote_repo_dir}/contrib/thrift-cmake/CMakeLists.txt'
  install -m 644 '${repo_root}/contrib/thrift-cmake/config.h.in' '${remote_repo_dir}/contrib/thrift-cmake/config.h.in'
fi
EOF
)

if [[ -n "${resolved_repo_url}" ]]; then
    remote_stage_cmd=$(
        cat <<EOF
set -euo pipefail
rm -rf '${remote_repo_dir}'
git clone '${resolved_repo_url}' '${remote_repo_dir}'
cd '${remote_repo_dir}'
if [[ -n '${repo_version}' ]]; then
  git fetch --tags --force origin '${repo_version}' || git fetch --tags --force origin
  git checkout '${repo_version}'
fi
git submodule sync --recursive
git submodule update --init --recursive
$(printf '%s' "${overlay_build_assets_cmd}")
EOF
    )
else
    remote_stage_cmd=$(
        cat <<EOF
set -euo pipefail
rm -rf '${remote_repo_dir}'
mkdir -p '${remote_repo_dir}'
tar --no-xattrs \
  --exclude=./build \
  --exclude=./.git \
  --exclude=*/.cache \
  --exclude=*/cmake-build-* \
  -cf - -C '${repo_root}' . | tar -xf - -C '${remote_repo_dir}'
test -f '${remote_repo_dir}/contrib/openldap/build/mkversion'
EOF
    )
fi

remote_build_cmd=$(
    cat <<EOF
set -euo pipefail
cd '${remote_repo_dir}'
resolved_image_revision='${image_revision}'
if [[ -z "\${resolved_image_revision}" ]] && git rev-parse HEAD >/dev/null 2>&1; then
  resolved_image_revision="\$(git rev-parse HEAD)"
fi
chmod +x docker/podman-build-local.sh
IMAGE_SOURCE='${image_source}' \
IMAGE_REVISION="\${resolved_image_revision}" \
IMAGE_CREATED='${image_created}' \
BUILD_JOBS='${build_jobs}' \
IMAGE_TAG='${image_tag}' \
BUILD_FORMAT='${build_format}' \
./docker/podman-build-local.sh .
EOF
)

echo "Using Podman VM staging directory: ${remote_repo_dir}"
if [[ -n "${resolved_repo_url}" ]]; then
    echo "Building repo ${resolved_repo_url} at version ${repo_version:-<default-branch>}"
else
    echo "Building the current local checkout snapshot"
fi

podman machine ssh "bash -lc $(printf '%q' "${remote_stage_cmd}")"
podman machine ssh "bash -lc $(printf '%q' "${remote_build_cmd}")"
