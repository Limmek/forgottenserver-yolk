FROM alpine:latest

RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories && \
    apk --update --no-cache add \
    curl \
    ca-certificates \
    nginx \
    git \
    php82 \
    php82-xml \
    php82-exif \
    php82-fpm \
    php82-soap \
    php82-openssl \
    php82-gmp \
    php82-dom \
    php82-pdo \
    php82-zip \
    php82-mysqli \
    php82-sqlite3 \
    php82-bcmath \
    php82-gd \
    php82-pdo_mysql \
    php82-pdo_sqlite \
    php82-gettext \
    php82-xmlreader \
    php82-bz2 \
    php82-iconv \
    php82-curl \
    php82-ctype \
    php82-phar \
    php82-fileinfo \
    php82-mbstring \
    php82-tokenizer \
    php82-simplexml

COPY --from=composer:latest  /usr/bin/composer /usr/bin/composer

RUN adduser -D -h /home/container container

USER container
ENV USER=container
ENV HOME=/home/container

WORKDIR /home/container
COPY ./entrypoint.sh /entrypoint.sh

RUN curl -fLo /home/container/nginx.conf https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/nginx.conf || { echo "Failed to download nginx config"; exit 1; }
RUN curl -fLo /home/container/start.sh https://raw.githubusercontent.com/Limmek/yolks/refs/heads/main/myaac/start.sh || { echo "Failed to download start script"; exit 1; } && chmod +x /home/container/start.sh

RUN git clone https://github.com/slawkens/myaac.git /home/container/public

CMD ["/bin/ash", "/entrypoint.sh"]