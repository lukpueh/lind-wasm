# Apply Docker best practices for downloading and extracting large files
# https://docs.docker.com/build/building/best-practices/#add-or-copy
# chmod is required to extract as user below
FROM scratch AS clang
ADD --chmod=644 https://github.com/llvm/llvm-project/releases/download/llvmorg-16.0.4/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04.tar.xz /clang.tar.xz

FROM ubuntu:latest

#####################
# SYSTEM DEPENDENCIES
#####################
RUN apt-get update && \
    apt-get install -y -qq \
        apt-transport-https \
        bash \
        binaryen \
        bison \
        build-essential \
        curl \
        g++ \
        g++-i686-linux-gnu \
        gawk \
        gcc \
        gcc-i686-linux-gnu \
        git \
        gnupg \
        golang \
        libssl-dev \
        libxml2 \
        openssl \
        python3 \
        sudo \
        unzip \
        vim \
        wget \
        zip

#####################
# USER SETUP
#####################
RUN usermod --login lind --move-home --home /home/lind ubuntu && \
    groupmod --new-name lind ubuntu
RUN echo "lind ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER lind
RUN mkdir /home/lind/lind-wasm
WORKDIR /home/lind/lind-wasm


###################
# USER DEPENDENCIES
###################
# Rust
# TODO: do we always need latest nightly? cache probably not invalidated by nightly change
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH="/home/lind/.cargo/bin:${PATH}"

# Extract Clang
RUN --mount=from=clang,target=/clang tar xf /clang/clang.tar.xz

###################
# GLIBC
###################
COPY --chown=lind:lind src/glibc src/glibc
RUN ./src/glibc/gen_sysroot.sh

###################
# WASMTIME
###################
COPY --chown=lind:lind src/wasmtime src/RawPOSIX src/fdtables src/sysdefs src/
RUN cargo build --manifest-path src/wasmtime/Cargo.toml

###################
# TESTS
###################
# NOTE: Code paths in lindtool.sh needed by wasmtestreport.py do not require bazel
# Also abs paths seem configurable
