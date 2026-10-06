#!/bin/bash

current_dir=$(pwd)
dbms=$1
image_tag=$2
# current date 
date=$(date --date="yesterday" '+%Y%m%d')

# check if image tag is set, else set it to 'latest'
if [ -z "$image_tag" ]; then
    image_tag="latest"
fi

# check if dbms is set
if [ -z "$dbms" ]; then
    echo "Please set dbms"
    exit 1
fi

# Build crate
if [ "$dbms" == "crate" ]; then
    docker build -t crate-source-build scripts/Docker/crate --no-cache
fi

# Build dolt
if [ "$dbms" == "dolt" ]; then
    cd $current_dir/resources
    rm -rf dolt
    git clone --depth 1 https://github.com/dolthub/dolt.git
    cd dolt/go
    go install ./cmd/dolt
fi

# Build firebird
if [ "$dbms" == "firebird" ]; then
    docker build -t firebird-source-build scripts/Docker/firebird --no-cache
fi

# Pull risingwave
if [ "$dbms" == "risingwave" ]; then
    docker pull risingwavelabs/risingwave:nightly-$date
fi

# download umbra
if [ "$dbms" == "umbra" ]; then
    cd $current_dir/resources
    rm -rf umbra
    rm umbra.tar.xz*
    wget https://db.in.tum.de/\~neumann/umbra.tar.xz
    tar -xf umbra.tar.xz
fi

# Pull tidb
if [ "$dbms" == "tidb" ]; then
    docker pull pingcap/tidb:nightly
fi

# Pull cockroachdb
if [ "$dbms" == "cockroachdb" ]; then
    docker pull cockroachdb/cockroach:latest
fi

# Pull postgres
if [ "$dbms" == "postgresql" ]; then
    docker pull postgres:latest
fi


# Pull mariadb
if [ "$dbms" == "mariadb" ]; then
    docker pull mariadb:latest
fi

# Pull mysql
if [ "$dbms" == "mysql" ]; then
    docker pull mysql:latest
fi

# Download and install duckdb
if [ "$dbms" == "duckdb" ]; then
    # The URL of the repository
    # REPO_URL="https://oss.sonatype.org/content/repositories/snapshots/org/duckdb/duckdb_jdbc/0.11.0-SNAPSHOT/"

    # # Use curl to fetch the contents of the repository
    # # This example assumes the repository lists files in a way that can be parsed with grep and sort
    # # This part of the script will likely need to be customized based on the actual repository structure
    # LATEST_JAR_URL=$(curl -s $REPO_URL | grep -oP 'href=".*[0-9]+\.jar"' | sort -r | head -1 | cut -d '"' -f 2)

    # # Full URL of the latest jar file
    # FULL_URL="$LATEST_JAR_URL"
    FULL_URL="https://artifacts.duckdb.org/duckdb-java/latest/java-jars.zip"

    # Download the latest jar file with wget
    cd $current_dir/resources
    rm -rf duckdb-jar
    mkdir -p duckdb-jar
    cd duckdb-jar

    wget $FULL_URL


    echo "Downloaded latest JAR file from $FULL_URL"

    unzip java-jars.zip

    cd ../..

    # Install the jar file
    mv resources/duckdb-jar/java-linux-amd64/duckdb_jdbc.jar $current_dir/target/duckdb_jdbc.jar
    mvn install:install-file -Dfile=target/duckdb_jdbc.jar -DgroupId=org.duckdb -DartifactId=duckdb_jdbc -Dversion=1.0.0 -Dpackaging=jar
    mvn package -DskipTests
fi

# Install sqlite
if [ "$dbms" == "sqlite" ]; then
    mvn clean
    cd $current_dir/resources/
    if [ -d "sqlite" ]; then
        rm -rf sqlite
    fi
    git clone --depth 1 https://github.com/sqlite/sqlite
    cd sqlite
    ./configure --enable-debug CC='clang'
    make
    cd ../sqlite-jdbc-official
    JAVA_HOME=    cd $current_dir/resources/sqlite-jdbc
    make clean
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/ make native SQLITE_OBJ=$current_dir/resources/sqlite/libsqlite3.so SQLITE_HEADER=$current_dir/resources/sqlite/sqlite3.h
    mvn package -DskipTests 
    mv target/sqlite-jdbc*.jar $current_dir/target/sqlite-jdbc.jar
    cd ../../
    mvn install:install-file -Dfile=target/sqlite-jdbc.jar -DgroupId=org.xerial -DartifactId=sqlite-jdbc -Dversion=3.40.0.0 -Dpackaging=jar
    mvn package -DskipTests
fi

if [ "$dbms" == "percona" ]; then
    docker pull percona/percona-server:latest
fi

if [ "$dbms" == "monetdb" ]; then
    docker build -t monetdb-source-build scripts/Docker/monetdb --no-cache
fi

if [ "$dbms" == "virtuoso" ]; then
    cd $current_dir/resources/vos-reference-docker
    NO_CACHE="--no-cache" ./build.sh
    cd ../../
fi

if [ "$dbms" == "h2" ]; then
    cd $current_dir/resources/
    rm -rf h2database
    git clone --depth 1 https://github.com/h2database/h2database.git
    cd h2database/h2
    mvn -DskipTests -Dmaven.compiler.source=11 -Dmaven.compiler.target=11 clean package
    cp target/h2*.jar $current_dir/target/h2.jar
    cd ../../../
    mvn install:install-file -Dfile=target/h2.jar -DgroupId=com.h2database -DartifactId=h2 -Dversion=2.1.214 -Dpackaging=jar
    mvn package -DskipTests
fi

