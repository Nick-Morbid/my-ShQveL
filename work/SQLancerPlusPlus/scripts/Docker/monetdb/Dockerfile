FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bison \
    build-essential \
    cmake \
    flex \
    git \
    gdb \
    libevent-dev \
    liblz4-dev \
    libprotobuf-c-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libunwind-dev \
    ncurses-dev \
    protobuf-c-compiler \
    python3 \
    tcl \
    uuid-dev \
    zlib1g-dev 


RUN groupadd -g 5000 monetdb && \
    useradd -u 5000 -g 5000 monetdb

WORKDIR /app

RUN git clone --depth 1 https://github.com/MonetDB/MonetDB.git

WORKDIR /app/MonetDB

RUN mkdir build && \
    cd build && \
    cmake .. && \
    cmake --build . && \
    cmake --build . --target install

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

EXPOSE 50000

ENTRYPOINT [ "/app/entrypoint.sh" ]