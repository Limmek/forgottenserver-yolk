FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

## Add container user
RUN useradd -m -d /home/container -s /bin/bash container
ENV USER=container HOME=/home/container

## Update base packages
RUN apt update && apt upgrade -y

## Install dependencies
# Update package list and install basic build tools
RUN apt update && apt install -y \
    gcc g++ gdb libc6-dev git wget curl tar zip unzip binutils xz-utils \
    cabextract iproute2 net-tools netcat-openbsd telnet libatomic1 \
    sqlite3 libsqlite3-dev locales ffmpeg bzip2 zlib1g-dev tini \
    cmake build-essential

# Install required libraries
RUN apt install -y \
    libssl-dev libcurl4-gnutls-dev liblua5.1-0-dev libluajit-5.1-dev \
    libevent-dev libmysqlclient-dev libicu-dev libjsoncpp-dev \
    libboost-system-dev libboost-iostreams-dev libpugixml-dev \
    libboost-locale-dev libboost-date-time-dev libboost-json-dev \
    libcrypto++-dev libfmt-dev libncurses-dev

# Install additional libraries (some may not be available in Ubuntu 24.04)
RUN apt install -y \
    libsdl2-2.0-0 libfontconfig1 libunwind8 libzip4 \
    || echo "Some packages not available, continuing..."

## Configure locale
RUN update-locale lang=en_US.UTF-8 && dpkg-reconfigure --frontend noninteractive locales

WORKDIR /home/container

STOPSIGNAL SIGINT

COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
