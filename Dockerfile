# Do all the cargo install stuff
FROM rust:slim-bookworm as builder

# Configure apt and install packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libpq-dev \
    curl \
    xz-utils \
    unzip

# /usr/local/cargo/bin/cargo
RUN curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
RUN curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/cargo-generate/cargo-generate/releases/download/v0.19.0/cargo-generate-v0.19.0-aarch64-unknown-linux-musl.tar.gz | tar xz -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/est31/cargo-udeps/releases/download/v0.1.45/cargo-udeps-v0.1.45-x86_64-unknown-linux-gnu.tar.gz | tar xz -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/mozilla/sccache/releases/download/v0.7.5/sccache-dist-v0.7.5-x86_64-unknown-linux-musl.tar.gz | tar xz -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/cargo-lambda/cargo-lambda/releases/download/v1.0.1/cargo-lambda-v1.0.1.x86_64-unknown-linux-musl.tar.gz | tar xz -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/shuttle-hq/shuttle/releases/download/v0.36.0/cargo-shuttle-v0.36.0-x86_64-unknown-linux-musl.tar.gz | tar xz -C ${CARGO_HOME}/bin
RUN curl -L https://github.com/rustwasm/wasm-bindgen/releases/download/0.2.90/wasm-bindgen-0.2.90-x86_64-unknown-linux-musl.tar.gz | tar xz -C ${CARGO_HOME}/bin

RUN curl -L https://github.com/leptos-rs/cargo-leptos/releases/download/0.2.5/cargo-leptos-x86_64-unknown-linux-musl.tar.xz | tar Jxf - -C ${CARGO_HOME}/bin


RUN curl https://github.com/watchexec/cargo-watch/releases/download/v8.5.2/cargo-watch-v8.5.2-x86_64-unknown-linux-musl.tar.xz -L -o cargo-watch.tar.xz \
    && tar -xf cargo-watch.tar.xz \
    && mv cargo-watch-v8.5.2-x86_64-unknown-linux-musl/cargo-watch /home

RUN find /usr/local/cargo/bin/ -maxdepth 1 -type f -not -name 'cargo' -exec mv {} /home/ \;


FROM rust:slim-bookworm
ARG MOLD_VERSION=2.4.0
ARG DOCKER_COMPOSE_VERSION=2.23.0

# This Dockerfile adds a non-root 'vscode' user with sudo access. However, for Linux,
# this user's GID/UID must match your local user UID/GID to avoid permission issues
# with bind mounts. Update USER_UID / USER_GID if yours is not 1000. See
# https://aka.ms/vscode-remote/containers/non-root-user for details.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Configure apt and install packages
RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ssh \
    sudo \
    pkg-config libssl-dev \
    # jq is used by earthly
    jq \
    # required by parcel or you can't npm install 
    build-essential \
    # Needed so that prost builds
    protobuf-compiler \
    # For musl builds
    musl-dev \
    musl-tools \
    musl \
    # Docker in Docker for Earthly
    apt-transport-https \
    ca-certificates \
    gnupg-agent \
    gnupg \
    software-properties-common \
    # psql
    postgresql-client \
    # mysql
    default-mysql-client \
    # Sqlite
    sqlite3 \
    libsqlite3-dev \
    # Install node.
    npm \
    nodejs \
    #
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -r /var/cache/* /var/lib/apt/lists/* \
    # Create a non-root user
    && groupadd --gid $USER_GID $USERNAME \
    && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME\
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    # Rust tools
    && rustup component add rustfmt clippy \
    && rustup toolchain install nightly \
    && rustup target add wasm32-unknown-unknown \
    # Add the musl toolchain
    && rustup target add x86_64-unknown-linux-musl \
    # Mold - Fast Rust Linker
    && curl -OL https://github.com/rui314/mold/releases/download/v$MOLD_VERSION/mold-$MOLD_VERSION-x86_64-linux.tar.gz \
    && tar -xf mold-$MOLD_VERSION-x86_64-linux.tar.gz \
    && mv ./mold-$MOLD_VERSION-x86_64-linux/bin/mold /usr/bin/ \
    && mv ./mold-$MOLD_VERSION-x86_64-linux/lib/mold/mold-wrapper.so /usr/bin/ \
    && rm mold-$MOLD_VERSION-x86_64-linux.tar.gz \
    && rm -rf ./mold-$MOLD_VERSION-x86_64-linux \
    && chmod +x /usr/bin/mold \
    # Docker compose
    && curl -L https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose 

USER $USERNAME


# Copy the binaries we built in builder container
COPY --chown=$USERNAME --from=builder /home/cargo-* $CARGO_HOME/bin
# Insert MOLD setup here
RUN echo '[target.x86_64-unknown-linux-gnu]\nlinker = "clang"\nrustflags = ["-C", "link-arg=-fuse-ld=/usr/bin/mold"]' > $CARGO_HOME/config.toml

RUN cargo binstall -y --continue-on-failure sqlx-cli cargo-bloat cargo-hack cargo-outdated cargo-hack
# cargo-lambda  cargo-shuttle 