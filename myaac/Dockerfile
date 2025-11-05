FROM php:8.2-fpm

RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libxml2-dev \
    libicu-dev \
    iproute2 \
    nginx \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip xml pdo pdo_mysql bcmath intl \
    && pecl install apcu \
    && docker-php-ext-enable apcu

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN useradd -m -d /home/container -s /bin/bash container \
    && sed -i 's/^user = .*/user = container/' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's/^group = .*/group = container/' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /usr/local/etc/php-fpm.d/www.conf

COPY --chown=container:container nginx/ /home/container/nginx/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && chown container:container /entrypoint.sh \
    && chown -R container:container /home/container

ENV USER=container
ENV HOME=/home/container
ENV NPM_CONFIG_CACHE=/home/container/.npm
WORKDIR /home/container

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD []
