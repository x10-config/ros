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
ARG CARGO_UDEPS_VERSION=0.1.45
ARG SCCACHE_VERSION=0.7.5
ARG CARGO_SHUTTLE_VERSION=0.36.0
ARG WASM_BINDGEN_VERSION=0.2.90
ARG CARGO_LEPTOS_VERSION=0.2.5
ARG CARGO_WATCH_VERSION=8.5.2
ARG CARGO_GENERATE_VERSION=0.19.0

# Install Cargo CLI tools that cannot be installed using binstall
RUN mkdir /cargo \
    && curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash \
    && mv ${CARGO_HOME}/bin/cargo-binstall /cargo \
    && curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C /cargo \
    && curl -L https://github.com/cargo-lambda/cargo-lambda/releases/download/v1.0.1/cargo-lambda-v1.0.1.x86_64-unknown-linux-musl.tar.gz | tar xz -C /cargo \
    && curl -L https://github.com/cargo-generate/cargo-generate/releases/download/v$CARGO_GENERATE_VERSION/cargo-generate-v$CARGO_GENERATE_VERSION-x86_64-unknown-linux-gnu.tar.gz | tar xz -C /cargo \
    && curl -L https://github.com/est31/cargo-udeps/releases/download/v$CARGO_UDEPS_VERSION/cargo-udeps-v$CARGO_UDEPS_VERSION-x86_64-unknown-linux-gnu.tar.gz | tar xz -C /tmp \
    && mv /tmp/cargo-udeps-v$CARGO_UDEPS_VERSION-x86_64-unknown-linux-gnu/cargo-udeps /cargo/cargo-udeps \
    && curl -L https://github.com/mozilla/sccache/releases/download/v$SCCACHE_VERSION/sccache-dist-v$SCCACHE_VERSION-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp \
    && mv /tmp/sccache-dist-v$SCCACHE_VERSION-x86_64-unknown-linux-musl/sccache-dist /cargo/sccache \
    && curl -L https://github.com/shuttle-hq/shuttle/releases/download/v$CARGO_SHUTTLE_VERSION/cargo-shuttle-v$CARGO_SHUTTLE_VERSION-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp \
    && mv /tmp/cargo-shuttle-x86_64-unknown-linux-musl-v$CARGO_SHUTTLE_VERSION/cargo-shuttle /cargo \
    && curl -L https://github.com/rustwasm/wasm-bindgen/releases/download/$WASM_BINDGEN_VERSION/wasm-bindgen-$WASM_BINDGEN_VERSION-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp \
    && mv /tmp/wasm-bindgen-$WASM_BINDGEN_VERSION-x86_64-unknown-linux-musl/wasm-bindgen /cargo \
    && curl -L https://github.com/leptos-rs/cargo-leptos/releases/download/$CARGO_LEPTOS_VERSION/cargo-leptos-x86_64-unknown-linux-musl.tar.xz | tar Jxf - -C /tmp \
    && mv /tmp/cargo-leptos-x86_64-unknown-linux-musl/cargo-leptos /cargo \
    && curl https://github.com/watchexec/cargo-watch/releases/download/v$CARGO_WATCH_VERSION/cargo-watch-v$CARGO_WATCH_VERSION-x86_64-unknown-linux-musl.tar.xz -L -o cargo-watch.tar.xz \
    && tar -xf cargo-watch.tar.xz \
    && mv cargo-watch-v$CARGO_WATCH_VERSION-x86_64-unknown-linux-musl/cargo-watch /cargo


FROM rust:slim-bookworm
ARG MOLD_VERSION=2.4.0
ARG DOCKER_COMPOSE_VERSION=2.23.0
ARG CLOAK_VERSION=1.20.0
ARG EARTHLY_VERSION=0.7.23

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
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -r /var/cache/* /var/lib/apt/lists/* \
    # Docker Engine for Earthly. https://docs.docker.com/engine/install/debian/
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && curl -fsSL "https://download.docker.com/linux/debian/gpg" | apt-key add - \
    && echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get -y update \
    && apt-get -y --no-install-recommends install docker-ce docker-ce-cli containerd.io \
    && apt-get autoremove -y && apt-get clean -y \
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
    && chmod +x /usr/local/bin/docker-compose \
    # Earthly
    && wget https://github.com/earthly/earthly/releases/download/v$EARTHLY_VERSION/earthly-linux-amd64 -O /usr/local/bin/earthly \
    && chmod +x /usr/local/bin/earthly \
    && /bin/sh -c "wget https://github.com/purton-tech/cloak/releases/download/v$CLOAK_VERSION/cloak-linux -O /usr/local/bin/cloak && chmod +x /usr/local/bin/cloak" 

USER $USERNAME


# Copy the binaries we built in builder container
COPY --chown=$USERNAME --from=builder /cargo/* $CARGO_HOME/bin

# Default Linker to MOLD
RUN echo '[target.x86_64-unknown-linux-gnu]\nlinker = "clang"\nrustflags = ["-C", "link-arg=-fuse-ld=/usr/bin/mold"]' > $CARGO_HOME/config.toml

# Install more cargo CLI using cargo-binstall
RUN cargo binstall -y --continue-on-failure sqlx-cli cargo-bloat cargo-hack cargo-outdated cargo-hack cargo-chef