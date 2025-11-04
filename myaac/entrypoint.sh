#!/bin/bash
set -e

# Default to port 80 if SERVER_PORT is not set
export APACHE_PORT=${SERVER_PORT:-80}

CONF_FILE="/home/container/000-default.conf"
APACHE_CONF_DIR="/etc/apache2"
SITES_AVAILABLE="/home/container/sites-available"
SITES_ENABLED="/home/container/sites-enabled"
DEFAULT_TEMPLATE="/etc/apache2/sites-available/default-template.conf"

# Create user-managed config, log, and runtime directories if they don't exist
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"
mkdir -p "/home/container/logs"
mkdir -p "${APACHE_RUN_DIR}"
chown container:container "${APACHE_RUN_DIR}"
chmod 755 "${APACHE_RUN_DIR}"
chown -R container:container "/home/container/logs"
chmod 755 "/home/container/logs"

# Clone and install MyAAC if it doesn't exist
if [ ! -d "/home/container/myaac" ]; then
    echo "MyAAC not found, cloning repository..."
    git clone https://github.com/slawkens/myaac.git /home/container/myaac
    cd /home/container/myaac
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    npm install --production

    # Set permissions based on MyAAC recommendations
    echo "Setting file permissions..."
    chown -R container:container /home/container/myaac
    chmod 660 /home/container/images/guilds
    chmod 660 /home/container/images/houses
    chmod 660 /home/container/images/gallery
    chmod -R 760 /home/container/system/cache

    cd /home/container
fi

# If user-editable config doesn't exist, copy the default template
if [ ! -f "$SITES_AVAILABLE/000-default.conf" ]; then
    echo "Copying default config to $SITES_AVAILABLE/000-default.conf"
    cp "$DEFAULT_TEMPLATE" "$SITES_AVAILABLE/000-default.conf"
fi

# Link the default config if it's not already linked
if [ ! -L "$SITES_ENABLED/000-default.conf" ] && [ -f "$SITES_AVAILABLE/000-default.conf" ]; then
    ln -s "$SITES_AVAILABLE/000-default.conf" "$SITES_ENABLED/000-default.conf"
fi

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