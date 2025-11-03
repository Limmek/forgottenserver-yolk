FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
    nginx \
    supervisor \
    git \
    curl \
    openssl \
    bash \
    shadow \
    npm \
    libzip-dev \
    libpng-dev \
    libxml2-dev \
    oniguruma-dev \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip opcache \
    && rm -rf /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN adduser -D -h /home/container container

WORKDIR /home/container
RUN git config --global --add safe.directory /home/container && \
    git clone https://github.com/slawkens/myaac.git . && \
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader && \
    npm install && \
    npm run production && \
    chmod 660 images/guilds && \
    chmod 660 images/houses && \
    chmod 660 images/gallery && \
    chmod -R 760 system/cache

RUN mkdir -p /home/container/tmp/nginx /run/php /var/log/supervisor \
    && chown -R container:container /home/container /run/php /var/log/supervisor

COPY --chown=container:container nginx.conf /etc/nginx/nginx.conf
COPY --chown=container:container supervisord.conf /etc/supervisord.conf
COPY --chown=container:container entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER container
ENV  USER=container HOME=/home/container
WORKDIR /home/container

EXPOSE 80

CMD ["/bin/bash", "/entrypoint.sh"]