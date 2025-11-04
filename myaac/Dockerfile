FROM php:8.2-apache

# Install system dependencies, PHP extensions, and helper tools as root
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
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip xml pdo pdo_mysql bcmath intl \
    && a2enmod rewrite
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create the non-root user and add it to the www-data group
RUN useradd -m -d /home/container -s /bin/bash container \
    && usermod -aG www-data container

# Set up Apache configuration template and entrypoint as root
COPY 000-default.conf /etc/apache2/sites-available/default-template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && sed -i 's|IncludeOptional sites-enabled/\*.conf|IncludeOptional /home/container/sites-enabled/\*.conf|' /etc/apache2/apache2.conf

# Switch to the non-root user for all subsequent operations
USER container
ENV  USER=container HOME=/home/container
WORKDIR /home/container

# Final WORKDIR and user for runtime
USER root
WORKDIR /home/container

# Expose port 80 (the entrypoint will handle the actual port)
EXPOSE 80

# Set the entrypoint to our custom script, which will start Apache
ENTRYPOINT ["/entrypoint.sh"]
CMD []
