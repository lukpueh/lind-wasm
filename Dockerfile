# syntax=docker/dockerfile:1.7-labs
# (use non-stable syntax for convenient --parents option in COPY command)

# Download clang
FROM scratch AS clang
ADD https://github.com/llvm/llvm-project/releases/download/llvmorg-16.0.4/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04.tar.xz /clang.tar.xz

FROM ubuntu:latest

#####################
# SYSTEM DEPENDENCIES
#####################
# * glibc deps as per INSTALL
#   * gcc not installed, because we use clang
#   * required cross-compilation header files installed via libc6-dev-i386-cross
# * build-essential, curl, ca-certificates needed by rust installer (and untar clang?)
# * libxml2 needed by clang
RUN apt-get update && \
    apt-get install -y --no-install-recommends -qq \
        make \
        libc6-dev-i386-cross \
        binutils \
        gawk \
        bison \
        sed \
        python3 \
        build-essential \
        curl \
        ca-certificates \
        libxml2 \
    && rm -rf /var/lib/apt/lists/*


###################
# USER DEPENDENCIES
###################
# Install pinned rust nightly version (known to work)
# TODO: Figure out why newer versions break the build and unpin
# TODO: Beware of RUN layer caching: cache not invalidated by remote change
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain nightly-2025-06-01
ENV PATH="/root/.cargo/bin:${PATH}"

# Extract Clang
# see best practices for downloading and extracting large files
# https://docs.docker.com/build/building/best-practices/#add-or-copy
RUN --mount=from=clang,target=/clang tar xf /clang/clang.tar.xz

###################
# Build GLIBC
###################
COPY src/glibc src/glibc
RUN ./src/glibc/gen_sysroot.sh

###################
# Build WASMTIME
###################
COPY --parents src/wasmtime src/RawPOSIX src/fdtables src/sysdefs .
RUN cargo build --manifest-path src/wasmtime/Cargo.toml --release

# ###################
# # Run TESTS
# ###################
COPY --parents scripts tests tools skip_test_cases.txt .
RUN LIND_WASM_BASE=/  LIND_FS_ROOT=/src/RawPOSIX/tmp ./scripts/wasmtestreport.py
