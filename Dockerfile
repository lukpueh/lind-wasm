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

RUN apt update -qq && apt install -y -qq bazel

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
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH="/home/lind/.cargo/bin:${PATH}"

# Clang
# See "ADD is better than manually adding files using something like wget and tar" in
# https://docs.docker.com/build/building/best-practices/#add-or-copy
RUN curl -sL https://github.com/llvm/llvm-project/releases/download/llvmorg-16.0.4/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04.tar.xz | \
        tar -xvJ

###################
# GLIBC
###################
COPY src/glibc src/glibc
RUN cp -r src/glibc/wasi clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04/lib/clang/16/lib


###################
# WASMTIME
###################


###################
# TESTS
###################
# NOTE: Code paths in lindtool.sh needed by wasmtestreport.py do not require bazel
# Also abs paths seem configurable


