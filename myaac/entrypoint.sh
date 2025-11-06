#!/bin/bash
set -euo pipefail

cd /home/container

STARTUP=${STARTUP:-None}
WEB_PORT=${SERVER_PORT:-8080}
SERVER_NAME=${SERVER_NAME:-_}
WEB_ROOT=${WEB_ROOT:-/home/container/myaac}
PHP_FPM_UPSTREAM=${PHP_FPM_UPSTREAM:-127.0.0.1:9000}
NGINX_CONFIG_PATH=${NGINX_CONFIG_PATH:-/home/container/nginx/nginx.conf}
NGINX_DEFAULT_SERVER=${NGINX_DEFAULT_SERVER:-/home/container/nginx/default.conf}
NGINX_FASTCGI_PARAMS=${NGINX_FASTCGI_PARAMS:-/home/container/nginx/fastcgi_params}
NGINX_MIME_TYPES=${NGINX_MIME_TYPES:-/home/container/nginx/mime.types}

if command -v ip >/dev/null 2>&1; then
    INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
else
    INTERNAL_IP="127.0.0.1"
    echo "Warning: 'ip' command not found; INTERNAL_IP defaulting to ${INTERNAL_IP}" >&2
fi
export INTERNAL_IP

export WEB_PORT SERVER_NAME WEB_ROOT PHP_FPM_UPSTREAM

mkdir -p /home/container/.tmp
mkdir -p /home/container/logs
mkdir -p /home/container/nginx
touch /home/container/logs/access.log /home/container/logs/error.log

if [ ! -d "${WEB_ROOT}" ]; then
    echo "MyAAC source not found at ${WEB_ROOT}, cloning repository..."
    git clone https://github.com/slawkens/myaac.git "${WEB_ROOT}"
    cd "${WEB_ROOT}"
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    npm install --production

    echo "Setting file permissions..."
    chmod 660 images/guilds || true
    chmod 660 images/houses || true
    chmod 660 images/gallery || true
    chmod -R 760 system/cache || true
    cd /home/container
fi

if [ ! -f "${NGINX_CONFIG_PATH}" ]; then
    echo "Nginx config ${NGINX_CONFIG_PATH} missing; downloading default copy..."
    mkdir -p "$(dirname "${NGINX_CONFIG_PATH}")"
    curl -fSL "https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/nginx/nginx.conf" -o "${NGINX_CONFIG_PATH}" || {
        echo "Failed to download Nginx configuration" >&2
        exit 1
    }
fi

if [ ! -f "${NGINX_DEFAULT_SERVER}" ]; then
    echo "Nginx default server ${NGINX_DEFAULT_SERVER} missing; downloading default copy..."
    mkdir -p "$(dirname "${NGINX_DEFAULT_SERVER}")"
    curl -fSL "https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/nginx/default.conf" -o "${NGINX_DEFAULT_SERVER}" || {
        echo "Failed to download Nginx default server block" >&2
        exit 1
    }
fi

if [ ! -f "${NGINX_FASTCGI_PARAMS}" ]; then
    echo "Nginx fastcgi_params ${NGINX_FASTCGI_PARAMS} missing; downloading default copy..."
    mkdir -p "$(dirname "${NGINX_FASTCGI_PARAMS}")"
    curl -fSL "https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/nginx/fastcgi_params" -o "${NGINX_FASTCGI_PARAMS}" || {
        echo "Failed to download Nginx fastcgi_params" >&2
        exit 1
    }
fi

if [ ! -f "${NGINX_MIME_TYPES}" ]; then
    echo "Nginx mime.types ${NGINX_MIME_TYPES} missing; downloading default copy..."
    mkdir -p "$(dirname "${NGINX_MIME_TYPES}")"
    curl -fSL "https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/nginx/mime.types" -o "${NGINX_MIME_TYPES}" || {
        echo "Failed to download Nginx mime.types" >&2
        exit 1
    }
fi

DB_FILE="${WEB_ROOT}/system/database.php"
if [ -f "${DB_FILE}" ] && ! grep -q "'port' => @\$config\['database_port'\]" "${DB_FILE}"; then
    echo "Adding missing database port configuration..."
    sed -i "0,/'host' => \$config\['database_host'\],/s//'host' => \$config['database_host'],\\n\\t\\t'port' => @\$config['database_port'],/" "${DB_FILE}" || true
fi

sed -i "0,/listen [0-9]\+;/s//listen ${WEB_PORT};/" "${NGINX_DEFAULT_SERVER}" || true
sed -i "0,/listen \[::\]:[0-9]\+;/s//listen [::]:${WEB_PORT};/" "${NGINX_DEFAULT_SERVER}" || true

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

    wait -n "${PHP_FPM_PID}" "${NGINX_PID}"
    exit_code=$?
    wait "${PHP_FPM_PID}" 2>/dev/null || true
    wait "${NGINX_PID}" 2>/dev/null || true
    return "${exit_code}"
}

echo "Starting server stack..."

if [ "${STARTUP}" = "null" ]; then
    start_services
    exit $?
else
    MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
    echo ":/home/container$ ${MODIFIED_STARTUP}"
    eval "${MODIFIED_STARTUP}"
fi
