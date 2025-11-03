FROM alpine:latest

RUN apk --update --no-cache add curl ca-certificates nginx
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories
RUN apk --update --no-cache add php8 php8-xml php8-exif php8-fpm php8-soap php8-openssl php8-gmp php8-dom php8-pdo php8-zip php8-mysqli php8-sqlite3 php8-bcmath php8-gd php8-pdo_mysql php8-pdo_sqlite php8-gettext php8-xmlreader php8-bz2 php8-iconv php8-curl php8-ctype php8-phar php8-fileinfo php8-mbstring php8-tokenizer php8-simplexml
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