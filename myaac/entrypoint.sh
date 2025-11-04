#!/bin/bash
set -e

# Default to port 80 if SERVER_PORT is not set
export APACHE_PORT=${SERVER_PORT:-80}

CONF_FILE="/home/container/000-default.conf"
APACHE_CONF_DIR="/etc/apache2"
SITES_AVAILABLE="/home/container/sites-available"
SITES_ENABLED="/home/container/sites-enabled"
DEFAULT_TEMPLATE="/etc/apache2/sites-available/default-template.conf"

# Create user-managed config directories if they don't exist
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"

# Clone and install MyAAC if it doesn't exist
if [ ! -d "/home/container/myaac" ]; then
    echo "MyAAC not found, cloning repository..."
    git clone https://github.com/slawkens/myaac.git /home/container/myaac
    cd /home/container/myaac
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    npm install
    chown -R container:www-data /home/container/myaac
    chmod -R 775 /home/container/myaac
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

# Update port in main apache config
sed -i "s/Listen 80/Listen ${APACHE_PORT}/g" "$APACHE_CONF_DIR/ports.conf"

# Update port in all user's virtual host configs
for conf in "$SITES_AVAILABLE"/*.conf; do
    if [ -f "$conf" ]; then
        sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:${APACHE_PORT}>/g" "$conf"
    fi
done

echo "Starting server..."

# Check if a custom startup command is provided
if [ -z "${STARTUP}" ]; then
    # If STARTUP is not set or is empty, use the default command
    echo "No custom startup command found, starting Apache directly."
    exec apache2-foreground
else
    # If STARTUP is set, process and run it.
    # This allows for Pterodactyl's variable substitution.
    MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
    echo ":/home/container$ ${MODIFIED_STARTUP}"

    # Execute the custom command
    eval "${MODIFIED_STARTUP}"
fi