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

# If user-editable config doesn't exist, copy the default template
if [ ! -f "$CONF_FILE" ]; then
    echo "Copying default config to $CONF_FILE"
    # We now copy it to the user-managed sites-available directory
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

echo "Starting Apache on port ${APACHE_PORT}..."

# Start Apache in the foreground
exec apache2-foreground