#!/bin/bash

echo "test" > $@

export GLIBC_BASE=$$PWD/src/glibc
export WORKSPACE=$$PWD

export CLANG=$$PWD/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04
export CC=$$CLANG/bin/clang

echo $$GLIBC_BASE >> $@
echo $$CLANG >> $@
echo $$CC >> $@

cd $$GLIBC_BASE
rm -rf build
./wasm-config.sh
cd build
make -j8 --keep-going 2>&1 THREAD_MODEL=posix | tee check.log || true

cd ../nptl

# Define common flags
CFLAGS="--target=wasm32-unknown-wasi -v -Wno-int-conversion -std=gnu11 -fgnu89-inline -matomics -mbulk-memory -O2 -g"
WARNINGS="-Wall -Wwrite-strings -Wundef -Wstrict-prototypes -Wold-style-definition"
EXTRA_FLAGS="-fmerge-all-constants -ftrapping-math -fno-stack-protector -fno-common"
EXTRA_FLAGS+=" -Wp,-U_FORTIFY_SOURCE -fmath-errno -fPIE -ftls-model=local-exec"
INCLUDE_PATHS="
    -I../include
    -I$$GLIBC_BASE/build/nptl
    -I$$GLIBC_BASE/build
    -I../sysdeps/lind
    -I../lind_syscall
    -I../sysdeps/unix/sysv/linux/i386/i686
    -I../sysdeps/unix/sysv/linux/i386
    -I../sysdeps/unix/sysv/linux/x86/include
    -I../sysdeps/unix/sysv/linux/x86
    -I../sysdeps/x86/nptl
    -I../sysdeps/i386/nptl
    -I../sysdeps/unix/sysv/linux/include
    -I../sysdeps/unix/sysv/linux
    -I../sysdeps/nptl
    -I../sysdeps/pthread
    -I../sysdeps/gnu
    -I../sysdeps/unix/inet
    -I../sysdeps/unix/sysv
    -I../sysdeps/unix/i386
    -I../sysdeps/unix
    -I../sysdeps/posix
    -I../sysdeps/i386/fpu
    -I../sysdeps/x86/fpu
    -I../sysdeps/i386
    -I../sysdeps/x86/include
    -I../sysdeps/x86
    -I../sysdeps/wordsize-32
    -I../sysdeps/ieee754/float128
    -I../sysdeps/ieee754/ldbl-96/include
    -I../sysdeps/ieee754/ldbl-96
    -I../sysdeps/ieee754/dbl-64
    -I../sysdeps/ieee754/flt-32
    -I../sysdeps/ieee754
    -I../sysdeps/generic
    -I..
    -I../libio
    -I.
"
SYS_INCLUDE="-nostdinc -isystem $$CLANG/lib/clang/16/include -isystem /usr/i686-linux-gnu/include"
DEFINES="-D_LIBC_REENTRANT -include $$GLIBC_BASE/build/libc-modules.h -DMODULE_NAME=libc"
EXTRA_DEFINES="-include ../include/libc-symbols.h -DPIC -DTOP_NAMESPACE=glibc"

$$CC $$CFLAGS $$WARNINGS $$EXTRA_FLAGS \
    $$INCLUDE_PATHS $$SYS_INCLUDE $$DEFINES $$EXTRA_DEFINES \
    -o $$GLIBC_BASE/build/nptl/pthread_create.o \
    -c pthread_create.c -MD -MP -MF $$GLIBC_BASE/build/nptl/pthread_create.o.dt \
    -MT $$GLIBC_BASE/build/nptl/pthread_create.o

$$CC $$CFLAGS $$WARNINGS $$EXTRA_FLAGS \
    $$INCLUDE_PATHS $$SYS_INCLUDE $$DEFINES $$EXTRA_DEFINES \
    -o $$GLIBC_BASE/build/lind_syscall.o \
    -c $$GLIBC_BASE/lind_syscall/lind_syscall.c

# Compile assembly files
cd ../ && \
$$CC --target=wasm32-wasi-threads -matomics \
    -o $$GLIBC_BASE/build/csu/wasi_thread_start.o \
    -c $$GLIBC_BASE/csu/wasm32/wasi_thread_start.s

$$CC --target=wasm32-wasi-threads -matomics \
    -o $$GLIBC_BASE/build/csu/set_stack_pointer.o \
    -c $$GLIBC_BASE/csu/wasm32/set_stack_pointer.s

GLIBC_BASE="/home/lind/lind-wasm/src/glibc"
# Define the source directory for object files (change ./build to your desired path)
src_dir="$GLIBC_BASE/build"

# Define paths for copying additional resources
include_source_dir="$GLIBC_BASE/target/include"
crt1_source_path="$GLIBC_BASE/lind_syscall/crt1.o"
lind_syscall_path="$GLIBC_BASE/build/lind_syscall.o" # Path to the lind_syscall.o file

# TARGET_TRIPLE = wasm32-wasi
TARGET_TRIPLE=wasm32-wasi-threads

# Define the output archive and sysroot directory
output_archive="$GLIBC_BASE/sysroot/lib/wasm32-wasi/libc.a"
sysroot_dir="$GLIBC_BASE/sysroot"

# First, remove the existing sysroot directory to start cleanly
rm -rf "$sysroot_dir"

# Find all .o files recursively in the source directory, ignoring stamp.o
object_files=$(find "$src_dir" -type f -name "*.o" ! \( -name "stamp.o" -o -name "argp-pvh.o" -o -name "repertoire.o" -o -name "static-stubs.o" \))

# Add the lind_syscall.o file to the list of object files
object_files="$object_files $lind_syscall_path"

# Check if object files were found
if [ -z "$object_files" ]; then
  echo "No suitable .o files found in '$src_dir'."
  exit 1
fi

# Create the sysroot directory structure
mkdir -p "$sysroot_dir/include/wasm32-wasi" "$sysroot_dir/lib/wasm32-wasi"

# Pack all found .o files into a single .a archive
${CLANG:=/home/lind/lind-wasm/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04}/bin/llvm-ar rcs "$output_archive" $object_files
"$CLANG/bin/llvm-ar" crs "$GLIBC_BASE/sysroot/lib/wasm32-wasi/libpthread.a"

# Check if llvm-ar succeeded
if [ $? -eq 0 ]; then
  echo "Successfully created $output_archive with the following .o files:"
  echo "$object_files"
else
  echo "Failed to create the archive."
  exit 1
fi

# Copy all files from the external include directory to the new sysroot include directory
cp -r "$include_source_dir"/* "$sysroot_dir/include/wasm32-wasi/"

# Copy the crt1.o file into the new sysroot lib directory
cp "$crt1_source_path" "$sysroot_dir/lib/wasm32-wasi/"

