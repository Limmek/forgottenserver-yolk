#!/bin/bash
set -e

# Default to port 8080 if SERVER_PORT is not set
export APACHE_PORT=${SERVER_PORT:-8080}

APACHE_BASE_DIR="/home/container/apache"
ROOT_CONF="${APACHE_BASE_DIR}/000-default.conf"
APACHE_CONF_DIR="/etc/apache2"
SITES_AVAILABLE="${APACHE_BASE_DIR}/sites-available"
SITES_ENABLED="${APACHE_BASE_DIR}/sites-enabled"
DEFAULT_TEMPLATE="/etc/apache2/sites-available/default-template.conf"
LEGACY_ROOT_CONF="/home/container/000-default.conf"
LEGACY_SITES_AVAILABLE="/home/container/sites-available"
LEGACY_SITES_ENABLED="/home/container/sites-enabled"

# Create user-managed config, log, and runtime directories if they don't exist
mkdir -p "$APACHE_BASE_DIR"
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"
mkdir -p "/home/container/logs"
mkdir -p "${APACHE_RUN_DIR}"
chmod 755 "$SITES_AVAILABLE" "$SITES_ENABLED"
chmod 755 "${APACHE_RUN_DIR}"
chmod 755 "/home/container/logs"

# Migrate legacy Apache config locations to the new /home/container/apache structure
if [ -f "$LEGACY_ROOT_CONF" ] && [ ! -f "$ROOT_CONF" ]; then
    mv "$LEGACY_ROOT_CONF" "$ROOT_CONF"
fi

if [ -d "$LEGACY_SITES_AVAILABLE" ] && [ ! -L "$LEGACY_SITES_AVAILABLE" ] && [ "$LEGACY_SITES_AVAILABLE" != "$SITES_AVAILABLE" ]; then
    cp -a "$LEGACY_SITES_AVAILABLE/." "$SITES_AVAILABLE/" 2>/dev/null || true
    rm -rf "$LEGACY_SITES_AVAILABLE"
fi
ln -sfn "$SITES_AVAILABLE" "$LEGACY_SITES_AVAILABLE"

if [ -d "$LEGACY_SITES_ENABLED" ] && [ ! -L "$LEGACY_SITES_ENABLED" ] && [ "$LEGACY_SITES_ENABLED" != "$SITES_ENABLED" ]; then
    cp -a "$LEGACY_SITES_ENABLED/." "$SITES_ENABLED/" 2>/dev/null || true
    rm -rf "$LEGACY_SITES_ENABLED"
fi
ln -sfn "$SITES_ENABLED" "$LEGACY_SITES_ENABLED"

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
sed -i "s/^Listen .*/Listen ${APACHE_PORT}/" "$APACHE_CONF_DIR/ports.conf"
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
