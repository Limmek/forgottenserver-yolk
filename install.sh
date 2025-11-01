#!/bin/bash
set -euo pipefail

# This script assumes build dependencies are already present in the image.
# It fetches the Forgotten Server sources, rebuilds when necessary, and
# ensures configuration files remain intact under /mnt/server.

backup_existing_config() {
    local backup_dir=""
    if [ -f config.lua ]; then
        backup_dir=$(mktemp -d)
        cp config.lua "${backup_dir}/config.lua"
    fi
    echo "${backup_dir}"
}

restore_existing_config() {
    local backup_dir="$1"
    if [ -n "${backup_dir}" ] && [ -f "${backup_dir}/config.lua" ]; then
        cp "${backup_dir}/config.lua" config.lua
        echo "Preserved existing config.lua"
        rm -rf "${backup_dir}"
    fi
}

TARGET_DIR=/mnt/server
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

RAW_GIT_ADDRESS=${GIT_ADDRESS:-""}
BRANCH=${BRANCH:-"main"}

if [ -z "${RAW_GIT_ADDRESS}" ]; then
    echo "ERROR: GIT_ADDRESS environment variable must be provided"
    exit 1
fi

if [[ ${RAW_GIT_ADDRESS} != *.git ]]; then
    RAW_GIT_ADDRESS="${RAW_GIT_ADDRESS}.git"
fi

AUTH_GIT_ADDRESS="${RAW_GIT_ADDRESS}"
if [ -n "${USERNAME:-}" ] && [ -n "${ACCESS_TOKEN:-}" ]; then
    echo "Using authenticated git access"
    AUTH_GIT_ADDRESS="https://${USERNAME}:${ACCESS_TOKEN}@$(echo -e "${RAW_GIT_ADDRESS}" | cut -d/ -f3-)"
else
    echo "Using anonymous git access"
fi

should_rebuild=false

if [ -d .git ]; then
    echo "Git repository exists. Checking for updates..."
    if [ -f .git/config ]; then
        ORIGIN=$(git config --get remote.origin.url)
        if [ "${ORIGIN}" == "${AUTH_GIT_ADDRESS}" ] || [ "${ORIGIN}" == "${RAW_GIT_ADDRESS}" ] || [[ "${ORIGIN}" == *"$(echo "${RAW_GIT_ADDRESS}" | cut -d/ -f4-)"* ]]; then
            echo "Fetching latest changes from ${BRANCH}"
            git fetch origin
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse "origin/${BRANCH}")
            if [ "${LOCAL}" != "${REMOTE}" ]; then
                echo "Updates detected. Resetting to origin/${BRANCH}"
                git reset --hard "origin/${BRANCH}"
                git submodule update --init --recursive
                should_rebuild=true
            else
                echo "Repository already up to date."
                if [ ! -f tfs ]; then
                    echo "Existing binary missing. Scheduling rebuild."
                    should_rebuild=true
                fi
            fi
        else
            echo "Repository origin mismatch. Expected ${RAW_GIT_ADDRESS}, found ${ORIGIN}. Re-cloning..."
            backup_dir=$(backup_existing_config)
            find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            git clone --recursive --single-branch --branch "${BRANCH}" "${AUTH_GIT_ADDRESS}" .
            restore_existing_config "${backup_dir}"
            should_rebuild=true
        fi
    else
        echo "Invalid git repository detected. Re-cloning..."
        backup_dir=$(backup_existing_config)
        find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        git clone --recursive --single-branch --branch "${BRANCH}" "${AUTH_GIT_ADDRESS}" .
        restore_existing_config "${backup_dir}"
        should_rebuild=true
    fi
else
    echo "No git repository found. Cloning sources..."
    backup_dir=$(backup_existing_config)
    find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    git clone --recursive --single-branch --branch "${BRANCH}" "${AUTH_GIT_ADDRESS}" .
    restore_existing_config "${backup_dir}"
    should_rebuild=true
fi

if [ "${should_rebuild}" = true ]; then
    echo "Building TFS..."
    rm -rf build
    mkdir -p build
    cd build
    cmake .. -DLUA_INCLUDE_DIR=/usr/include/luajit-2.1 -DLUA_LIBRARY=/usr/lib/x86_64-linux-gnu/libluajit-5.1.so
    make -j"$(nproc)"

    if [ -f tfs ]; then
        mv tfs "${TARGET_DIR}/"
        chmod +x "${TARGET_DIR}/tfs"
        echo "TFS rebuilt and deployed to ${TARGET_DIR}/tfs"
    else
        echo "ERROR: TFS build failed"
        exit 1
    fi

    cd "${TARGET_DIR}"
else
    echo "Skipping rebuild; binaries already current."
fi

if [ ! -f config.lua ] && [ -f config.lua.dist ]; then
    cp config.lua.dist config.lua
    echo "Created config.lua from template"
fi

echo "Installation/update complete!"