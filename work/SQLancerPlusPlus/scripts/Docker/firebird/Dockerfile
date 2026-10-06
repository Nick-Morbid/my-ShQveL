FROM ubuntu:22.04

WORKDIR /app
RUN apt-get update --yes && apt-get install git autoconf gcc g++ automake libtool zlib1g-dev libicu-dev libtommath-dev libtomcrypt-dev make cmake ca-certificates libexpat1-dev libncurses5-dev libsdl1.2-dev unzip --yes --no-install-recommends

RUN git clone --depth 1 https://github.com/FirebirdSQL/firebird.git
WORKDIR /app/firebird

RUN ./autogen.sh && make && echo -e '\n masterkey\n' | make install

ENV PATH /usr/local/firebird/bin:${PATH}

EXPOSE 3050

COPY schema.sql /app/firebird

RUN isql -input /app/firebird/schema.sql

ENTRYPOINT [ "firebird"]