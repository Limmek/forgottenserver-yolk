#!/bin/bash
set -euo pipefail

cd /home/container

# Ensure frequently used environment variables are initialised
STARTUP=${STARTUP:-None}
WEB_PORT=${SERVER_PORT:-8080}
SERVER_NAME=${SERVER_NAME:-_}
WEB_ROOT=${WEB_ROOT:-/home/container/myaac}
PHP_FPM_UPSTREAM=${PHP_FPM_UPSTREAM:-127.0.0.1:9000}
NGINX_CONFIG_PATH=${NGINX_CONFIG_PATH:-/home/container/nginx/nginx.conf}
NGINX_DEFAULT_SERVER=${NGINX_DEFAULT_SERVER:-/home/container/nginx/default.conf}

# Make internal Docker IP address available to processes.
if command -v ip >/dev/null 2>&1; then
    INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
else
    INTERNAL_IP="127.0.0.1"
    echo "Warning: 'ip' command not found; INTERNAL_IP defaulting to ${INTERNAL_IP}" >&2
fi
export INTERNAL_IP

export WEB_PORT SERVER_NAME WEB_ROOT PHP_FPM_UPSTREAM

# Prepare runtime directories and log files
mkdir -p /home/container/logs
mkdir -p /home/container/nginx
touch /home/container/logs/access.log /home/container/logs/error.log

# Clone and install MyAAC if it doesn't exist yet
if [ ! -d "${WEB_ROOT}" ]; then
    echo "MyAAC source not found at ${WEB_ROOT}, cloning repository..."
    git clone https://github.com/slawkens/myaac.git "${WEB_ROOT}"
    cd "${WEB_ROOT}"
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    npm install --production

    # Set permissions based on MyAAC recommendations
    echo "Setting file permissions..."
    chmod 660 images/guilds || true
    chmod 660 images/houses || true
    chmod 660 images/gallery || true
    chmod -R 760 system/cache || true
    cd /home/container
fi

# Validate provided Nginx configuration files
if [ ! -f "${NGINX_CONFIG_PATH}" ]; then
    echo "ERROR: Expected nginx config at ${NGINX_CONFIG_PATH} but it was not found." >&2
    exit 1
fi

if [ ! -f "${NGINX_DEFAULT_SERVER}" ]; then
    echo "Warning: Default server block ${NGINX_DEFAULT_SERVER} not found." >&2
fi

echo "Using nginx config ${NGINX_CONFIG_PATH}"

PHP_FPM_PID=""
NGINX_PID=""

cleanup() {
    if [ -n "${NGINX_PID}" ] && kill -0 "${NGINX_PID}" >/dev/null 2>&1; then
        kill "${NGINX_PID}" >/dev/null 2>&1 || true
    fi
    if [ -n "${PHP_FPM_PID}" ] && kill -0 "${PHP_FPM_PID}" >/dev/null 2>&1; then
        kill "${PHP_FPM_PID}" >/dev/null 2>&1 || true
    fi
}

start_services() {
    echo "Starting php-fpm..."
    php-fpm --nodaemonize --allow-to-run-as-root &
    PHP_FPM_PID=$!

    echo "Starting nginx..."
    nginx -c "${NGINX_CONFIG_PATH}" -g "daemon off;" &
    NGINX_PID=$!

    trap cleanup EXIT INT TERM

    # Wait for either process to exit, then cascade shutdown
    wait -n "${PHP_FPM_PID}" "${NGINX_PID}"
    exit_code=$?
    wait "${PHP_FPM_PID}" 2>/dev/null || true
    wait "${NGINX_PID}" 2>/dev/null || true
    return "${exit_code}"
}

echo "Starting server stack..."

if [ "${STARTUP}" = "None" ]; then
    start_services
    exit $?
else
    MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
    echo ":/home/container$ ${MODIFIED_STARTUP}"
    eval "${MODIFIED_STARTUP}"
fi
