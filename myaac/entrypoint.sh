#!/bin/bash
set -e

# Default to port 8080 if SERVER_PORT is not set
export APACHE_PORT=${SERVER_PORT:-8080}

APACHE_BASE_DIR="/home/container/apache"
ROOT_CONF="${APACHE_BASE_DIR}/000-default.conf"
APACHE_CONF_DIR="/etc/apache2"
PORTS_CONF="${APACHE_BASE_DIR}/ports.conf"
SITES_AVAILABLE="${APACHE_BASE_DIR}/sites-available"
SITES_ENABLED="${APACHE_BASE_DIR}/sites-enabled"
DEFAULT_TEMPLATE="/etc/apache2/sites-available/default-template.conf"
DEFAULT_PORTS_CONF="${APACHE_CONF_DIR}/ports.conf"


# Create user-managed config, log, and runtime directories if they don't exist
mkdir -p "$APACHE_BASE_DIR"
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"
mkdir -p "/home/container/logs"
mkdir -p "${APACHE_RUN_DIR}"
chmod 755 "$SITES_AVAILABLE" "$SITES_ENABLED"
chmod 755 "${APACHE_RUN_DIR}"
chmod 755 "/home/container/logs"

# Ensure a writable ports.conf managed from /home/container
if [ ! -f "$PORTS_CONF" ]; then
    if [ -f "$DEFAULT_PORTS_CONF" ]; then
        cp "$DEFAULT_PORTS_CONF" "$PORTS_CONF"
    else
        echo "Listen ${APACHE_PORT}" > "$PORTS_CONF"
    fi
fi
chmod 644 "$PORTS_CONF" 2>/dev/null || true

# Clone and install MyAAC if it doesn't exist
if [ ! -d "/home/container/myaac" ]; then
    echo "MyAAC not found, cloning repository..."
    git clone https://github.com/slawkens/myaac.git /home/container/myaac
    cd /home/container/myaac
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    npm install --production

    # Set permissions based on MyAAC recommendations
    echo "Setting file permissions..."
    chmod 660 images/guilds
    chmod 660 images/houses
    chmod 660 images/gallery
    chmod -R 760 system/cache

    cd /home/container
fi

# If user-editable config doesn't exist, copy the default template
# Ensure a user-editable root Apache config exists and is linked
if [ ! -f "$ROOT_CONF" ]; then
    echo "Creating default Apache config at $ROOT_CONF"
    cp "$DEFAULT_TEMPLATE" "$ROOT_CONF"
fi

if [ ! -L "$SITES_AVAILABLE/000-default.conf" ] || [ "$(readlink -f "$SITES_AVAILABLE/000-default.conf")" != "$ROOT_CONF" ]; then
    rm -f "$SITES_AVAILABLE/000-default.conf"
    ln -s "$ROOT_CONF" "$SITES_AVAILABLE/000-default.conf"
fi

# Link the default config into sites-enabled
if [ ! -L "$SITES_ENABLED/000-default.conf" ] || [ "$(readlink -f "$SITES_ENABLED/000-default.conf")" != "$ROOT_CONF" ]; then
    rm -f "$SITES_ENABLED/000-default.conf"
    ln -s "$ROOT_CONF" "$SITES_ENABLED/000-default.conf"
fi

# Update Apache configuration to listen on the requested port
if grep -qE '^Listen [0-9]+' "$PORTS_CONF"; then
    sed -i "0,/^Listen [0-9]\+/{s//Listen ${APACHE_PORT}/}" "$PORTS_CONF"
else
    echo "Listen ${APACHE_PORT}" >> "$PORTS_CONF"
fi
sed -i "0,/<VirtualHost \*:[0-9]\+>/{s//<VirtualHost *:${APACHE_PORT}>/}" "$ROOT_CONF"

export APACHE_RUN_USER=container
export APACHE_RUN_GROUP=container

echo "Starting server..."

# Check if the startup command is set to "None"
if [ "${STARTUP}" == "None" ]; then
    # If STARTUP is "None", use the default command
    echo "STARTUP is 'None', starting Apache directly."
    exec apache2-foreground
else
    # If STARTUP is set to anything else, process and run it.
    # This allows for Pterodactyl's variable substitution.
    MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
    echo ":/home/container$ ${MODIFIED_STARTUP}"

    # Execute the custom command
    eval "${MODIFIED_STARTUP}"
fi
