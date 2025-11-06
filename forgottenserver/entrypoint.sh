#!/bin/bash
set -euo pipefail

cd /home/container

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

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

if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then 
    echo "Auto-update is enabled. Checking for updates..."
    
    # Set default values if not provided
    GIT_ADDRESS=${GIT_ADDRESS:-""}
    BRANCH=${BRANCH:-"main"}
    
    if [ -z "${GIT_ADDRESS}" ]; then
        echo "ERROR: GIT_ADDRESS environment variable is required for auto-update"
        exit 1
    fi
    
    # Ensure .git extension
    if [[ ${GIT_ADDRESS} != *.git ]]; then
        GIT_ADDRESS=${GIT_ADDRESS}.git
    fi
    
    # Setup authentication if provided
    if [ -n "${USERNAME}" ] && [ -n "${ACCESS_TOKEN}" ]; then
        echo "Using authenticated git access"
        GIT_ADDRESS="https://${USERNAME}:${ACCESS_TOKEN}@$(echo -e ${GIT_ADDRESS} | cut -d/ -f3-)"
    else
        echo "Using anonymous git access"
    fi
    
    should_rebuild=false
    
    # Check if TFS source code already exists
    if [ -d .git ]; then
        echo "Git repository exists. Checking for updates..."
        if [ -f .git/config ]; then
            echo "Loading info from git config"
            ORIGIN=$(git config --get remote.origin.url)
            
            if [ "${ORIGIN}" == "${GIT_ADDRESS}" ] || [[ "${ORIGIN}" == *"$(echo ${GIT_ADDRESS} | cut -d/ -f4-)"* ]]; then
                echo "Pulling latest from ${BRANCH} branch"
                git fetch origin
                
                # Check if there are any updates
                LOCAL=$(git rev-parse HEAD)
                REMOTE=$(git rev-parse origin/${BRANCH})
                
                if [ "$LOCAL" != "$REMOTE" ]; then
                    echo "Updates found. Pulling changes..."
                    changed_files=$(git diff --name-only "$LOCAL" "origin/${BRANCH}")
                    git reset --hard origin/${BRANCH}
                    git submodule update --init --recursive

                    if echo "$changed_files" | grep -q '^src/'; then
                        echo "Changes detected in src/; rebuild required."
                        should_rebuild=true
                    else
                        echo "No changes in src/ detected; skipping rebuild."
                        if [ ! -f tfs ]; then
                            echo "TFS binary not found. Building..."
                            should_rebuild=true
                        fi
                    fi
                else
                    echo "No updates available. TFS is up to date."
                    # Only rebuild if TFS binary doesn't exist
                    if [ ! -f tfs ]; then
                        echo "TFS binary not found. Building..."
                        should_rebuild=true
                    fi
                fi
            else
                echo "Repository origin mismatch. Expected: ${GIT_ADDRESS}, Found: ${ORIGIN}"
                echo "Removing existing repository and re-cloning..."
                backup_dir=$(backup_existing_config)
                find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                git clone --recursive --single-branch --branch ${BRANCH} ${GIT_ADDRESS} .
                restore_existing_config "${backup_dir}"
                should_rebuild=true
            fi
        else
            echo "Invalid git repository found. Re-cloning..."
            backup_dir=$(backup_existing_config)
            find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            git clone --recursive --single-branch --branch ${BRANCH} ${GIT_ADDRESS} .
            restore_existing_config "${backup_dir}"
            should_rebuild=true
        fi
    else
        echo "No git repository found. Cloning TFS source code..."
        backup_dir=$(backup_existing_config)
        find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        git clone --recursive --single-branch --branch ${BRANCH} ${GIT_ADDRESS} .
        restore_existing_config "${backup_dir}"
        should_rebuild=true
    fi
    
    # Build TFS if needed
    if [ "$should_rebuild" = true ]; then
        echo "Building TFS..."
        rm -rf build
        mkdir -p build
        cd build
        if [ "${BUILD:-0}" = "1" ]; then BUILD_TYPE="Debug"; else BUILD_TYPE="Release"; fi
        cmake .. -DLUA_INCLUDE_DIR=/usr/include/luajit-2.1 -DLUA_LIBRARY=/usr/lib/x86_64-linux-gnu/libluajit-5.1.so -D CMAKE_BUILD_TYPE=${BUILD_TYPE}
        make
        
        # Move TFS if it was built and make it executable
        if [ -f tfs ]; then
            mv tfs /home/container/
            chmod +x /home/container/tfs
            echo "TFS has been built and moved to /home/container/"
        else
            echo "ERROR: TFS was not built!"
            exit 1
        fi
        
        cd /home/container
    fi
    
    # Copy config.lua.dist to config.lua if config.lua is missing
    if [ ! -f config.lua ]; then
        if [ -f config.lua.dist ]; then
            cp config.lua.dist config.lua
            echo "config.lua has been created from config.lua.dist"
        else
            echo "WARNING: config.lua.dist not found, cannot create config.lua"
        fi
    else
        echo "config.lua already exists"
    fi
    
    echo "Auto-update completed successfully!"
else
    echo "Auto-update is disabled. Skipping update check."
fi


# MyAAC need access to config.lua and data directory on a mounted volume since it can not access the container filesystem.
# Sync container config and data to mounted directory
if [ -n "${MOUNT_PATH:-}" ]; then
    mount_root="${MOUNT_PATH%/}"
    if ls -d "${mount_root}" >/dev/null 2>&1; then
        echo "Mount path ${mount_root} detected. Syncing data and config."

        mkdir -p "${mount_root}"

        # Sync config.lua if it changed
        if [ -f /home/container/config.lua ]; then
            mount_config="${mount_root}/config.lua"
            if [ ! -f "${mount_config}" ]; then
                cp /home/container/config.lua "${mount_config}"
                echo "Copied config.lua to mount."
            elif ! cmp -s /home/container/config.lua "${mount_config}"; then
                cp /home/container/config.lua "${mount_config}"
                echo "Updated config.lua on mount."
            else
                echo "config.lua unchanged; no update needed."
            fi
        else
            echo "config.lua not found in container; skipping config sync."
        fi

        # Sync data directory, preserving nested content
        if [ -d /home/container/data ]; then
            mkdir -p "${mount_root}/data"
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --delete --checksum /home/container/data/ "${mount_root}/data/"
                echo "Data directory synced to mount using rsync."
            else
                echo "rsync not available; performing full data copy."
                rm -rf "${mount_root}/data"
                mkdir -p "${mount_root}/data"
                cp -a /home/container/data/. "${mount_root}/data/"
            fi
        else
            echo "Data directory not found in container; skipping data sync."
        fi
    else
        echo "Mount path ${mount_root} not accessible. Skipping mount sync."
    fi
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}