FROM ubuntu:22.04

ARG USERNAME="crate"

WORKDIR /app
RUN apt-get update --yes && apt-get install git python3 python3-pip openjdk-11-jdk maven wget --yes --no-install-recommends && useradd -u 1000 -m ${USERNAME} -d /home/${USERNAME} && chmod 777 /app

RUN  git clone --depth 1  https://github.com/crate/crate.git
WORKDIR /app/crate

EXPOSE 4200 4300 5432

RUN mvn package -DskipTests=true 
RUN tar xvzf app/target/crate-*.tar.gz && mv crate-*/ crate-release

ENV PATH /app/crate/crate-release/bin:${PATH}
COPY docker-entrypoint.sh /
COPY --chown=1000:0 crate.yml /app/crate/crate-release/config/crate.yml

ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "crate"]
