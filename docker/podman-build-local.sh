#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}"

image_tag="${IMAGE_TAG:-clickhouse-oci-local}"
build_jobs="${BUILD_JOBS:-1}"
build_format="${BUILD_FORMAT:-docker}"
image_source="${IMAGE_SOURCE:-}"
image_revision="${IMAGE_REVISION:-}"
image_created="${IMAGE_CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

restore_broken_submodule_worktree() {
    local submodule_path="$1"
    local gitdir=".git/modules/${submodule_path}"
    local first_tracked_path
    local first_tracked_full_path

    if [[ ! -d "${gitdir}" || ! -f "${submodule_path}/.git" ]]; then
        return 0
    fi

    first_tracked_path="$(
        git --git-dir="${gitdir}" ls-tree -r --name-only HEAD 2>/dev/null | sed -n '1p'
    )"

    if [[ -z "${first_tracked_path}" ]]; then
        return 0
    fi

    first_tracked_full_path="${submodule_path}/${first_tracked_path}"

    if [[ -e "${first_tracked_full_path}" ]]; then
        return 0
    fi

    echo "Restoring tracked files for ${submodule_path}"
    git --git-dir="${gitdir}" --work-tree="${submodule_path}" checkout -f HEAD -- .
}

while read -r _ submodule_path; do
    restore_broken_submodule_worktree "${submodule_path}"
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$')

if [[ ! -f contrib/sysroot/README.md ]]; then
    echo "Missing initialized submodules in the local checkout." >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 2
fi

if [[ "${PREPARE_ONLY:-0}" == "1" ]]; then
    echo "Submodule worktree repair complete."
    exit 0
fi

exec podman build \
    --format "${build_format}" \
    --build-arg "BUILD_JOBS=${build_jobs}" \
    --build-arg "IMAGE_SOURCE=${image_source}" \
    --build-arg "IMAGE_REVISION=${image_revision}" \
    --build-arg "IMAGE_CREATED=${image_created}" \
    -t "${image_tag}" \
    "$@"
