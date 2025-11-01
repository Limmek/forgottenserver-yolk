#!/bin/bash
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
                    git reset --hard origin/${BRANCH}
                    git submodule update --init --recursive
                    should_rebuild=true
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
        cmake .. -DLUA_INCLUDE_DIR=/usr/include/luajit-2.1 -DLUA_LIBRARY=/usr/lib/x86_64-linux-gnu/libluajit-5.1.so
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

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}