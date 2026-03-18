#!/usr/bin/env bash

set -euo pipefail

jobs="${BUILD_JOBS}"
if [[ "${jobs}" == "0" ]]; then
    jobs="$(nproc)"
fi

if [[ ! -f /src/contrib/sysroot/README.md ]]; then
    echo "Build context is missing initialized ClickHouse submodules." >&2
    echo "Run: git submodule update --init --recursive before docker/podman build." >&2
    exit 2
fi

chmod +x /src/build-clickhouse.sh

build_args=(
    --skip-submodules
    --build-dir build
    --build-type "${BUILD_TYPE}"
    --target "${BUILD_TARGET}"
    --jobs "${jobs}"
    --cmake-arg "-DENABLE_TESTS=${ENABLE_TESTS}"
    --cmake-arg "-DENABLE_UTILS=${ENABLE_UTILS}"
    --cmake-arg "-DENABLE_RUST=${ENABLE_RUST}"
)

if [[ -n "${EXTRA_CMAKE_ARGS}" ]]; then
    while IFS= read -r arg; do
        [[ -n "${arg}" ]] && build_args+=(--cmake-arg "${arg}")
    done <<< "${EXTRA_CMAKE_ARGS}"
fi

export CC="clang-${LLVM_VERSION}" CXX="clang++-${LLVM_VERSION}"
/src/build-clickhouse.sh "${build_args[@]}"
test -x /src/build/programs/clickhouse
