This is an attempt to build fully static, self-contained LLVM tools and libraries.

## Goal

- static libries
  - libc++ (libc++.a, libc++abi.a, libunwind.a)
  - compiler-rt (clang_rt.crtbegin.o, clang_rt.crtend.o, libclang_rt.\*.a)
  - llvm IR, opt etc libs (libLLVMPasses.a, ...)
  - clang libs (libLLVMLibDriver.a, ...)
  - lld libs (libLLVMLinker.a, ...)
- statically-linked tools, linked with the above static libaries:
  - clang, lld, ar, ranlib, objdump etc

You should be able to build your own compiler suite by:

1. making a main.cc file that calls clang_main and/or lld_main
2. compiling that main.cc file with clang & lld
3. statically linking that main object with libc++, clang, lld and llvm libs
   so that the resulting executable does not require a dynamic linker to run
   (exception: on darwin it has to dynamically link with libSystem.dylib, but that's it)


## Build

TL;DR:

```sh
export LLVMBOX_BUILD_DIR=$HOME/tmp
utils/mktmpfs-build-dir.sh 16384 # limit to 16GB
./build.sh

# test full-featured program linking with llvm libs
./myclang/build.sh
```

Host requirements:

- compiler that can build clang (e.g. gcc)
- ninja or equivalent
- cmake 3
- python3
- bash

Tested host systems:

- Ubuntu 20 x86_64
- Alpine 3.16 x86_64
- macOS 10.15 x86_64
- macOS 12 aarch64

### Detailed build instructions

If you have a lot of RAM, it is usually much faster to build in a ramfs:

- Linux: `export LLVMBOX_BUILD_DIR=/dev/shm`
- Linux with tmpfs: `mkdir -p ~/tmp && sudo mount -t tmpfs -o size=16G tmpfs ~/tmp && export LLVMBOX_BUILD_DIR=$HOME/tmp`
- macOS: `utils/macos-tmpfs.sh ~/tmp && export LLVMBOX_BUILD_DIR=$HOME/tmp`


Define your build directory

```
export LLVMBOX_BUILD_DIR=build
```

Run all build scripts in order:

```
./build.sh
```

Run just some build scripts, starting with a prefix, for example:

```
./build.sh 02
```

Run build scripts a la carte, steps of your liking.
For example, to build the "stage1" compiler, run:

```
bash 010-llvm-source-stage1.sh
bash 010-zlib-stage1.sh
bash 019-llvm-stage1.sh
```


### Build problems

If the linker gets OOM killed, try setting NCPU to a smaller number than `nproc`:

```
export NCPU=4
bash 019-llvm-stage1.sh # or whatever step failed
```


----

## Test

The ultimate test is to be able to build "myclang", our own "custom clang" that links in all the code needed for clang (which is almost everything).

```sh
LLVM_ROOT=path-to-llvm-installation ./myclang/build.sh
```

For example:

```sh
LLVM_ROOT=$LLVMBOX_BUILD_DIR/llvm-x86_64-macos-none ./myclang/build.sh
```


### Test host compiler

After building the host compiler, you should be able to compile C++ programs:

```
$LLVMBOX_BUILD_DIR/llvm-host/bin/clang++ test/hello.cc -o test/hello_cc
test/hello_cc
```

The final program should be statically linked with libc++, ie. not contain any links to c++ libraries (but may contain links to shared host system libc.)

```
$LLVMBOX_BUILD_DIR/llvm-host/bin/llvm-objdump -p test/hello_cc | grep -E 'NEEDED|\.dylib'
```


### Test utilities

There are also wrapper scripts to help with testing, which invokes clang with the appropriate flags:

```sh
LLVM_ROOT=/dev/shm/llvm-host utils/cc test/hello.c -o test/hello_c
LLVM_ROOT=/dev/shm/llvm-host utils/c++ test/hello.cc -o test/hello_cc
```

Another useful utility is `utils/config` which prints compiler and linker flags. For example, it can be used to configure builds:

```sh
#!/bin/sh
export LLVM_ROOT=$HOME/tmp/llvm-x86_64-macos-none
MY_CXXFLAGS="$(utils/config --cxxflags)"
MY_LDFLAGS="$(utils/config --ldflags-cxx)"
"$LLVM_ROOT/bin/clang++" $MY_CXXFLAGS -c main.cc -o main.o
"$LLVM_ROOT/bin/clang++" $MY_LDFLAGS main.o -o myprogram
```


### Testing musl

Testing musl with host compiler (linux only)

```
export LLVMBOX_MUSL=$(echo $LLVMBOX_BUILD_DIR/musl-$(uname -m)-linux-*)
$LLVMBOX_BUILD_DIR/llvm-host/bin/clang \
  -isystem$LLVMBOX_MUSL/include \
  -nostartfiles $LLVMBOX_MUSL/lib/crt1.o \
  -nostdlib -L$LLVMBOX_MUSL/lib -lc \
  test/hello.c -o test/hello_c
test/hello_c
# this should not print anything:
$LLVMBOX_BUILD_DIR/llvm-host/bin/llvm-objdump -p test/hello_c | grep NEEDED
```


This dose _NOT_ work for C++ using the host compiler since the host compiler is likely linked with glibc, not musl. I.e:

```
$LLVMBOX_BUILD_DIR/llvm-host/bin/clang++ \
  -nostdinc++ -isystem$LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1 \
  -I$LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1 \
  -I$(echo $LLVMBOX_BUILD_DIR/llvm-host/include/$(uname -m)-unknown-linux-*)/c++/v1 \
  -L$(echo $LLVMBOX_BUILD_DIR/llvm-host/lib/$(uname -m)-unknown-linux-*) \
  -nostdlib++ -L$LLVMBOX_BUILD_DIR/llvm-host/lib \
  -lc++ \
  \
  -isystem$LLVMBOX_MUSL/include \
  -nostartfiles $LLVMBOX_MUSL/lib/crt1.o \
  -nostdlib -L$LLVMBOX_MUSL/lib -lc \
  test/hello.cc -o test/hello_cc

LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1/__locale:572:13: error: unknown type name 'mask'
    bool is(mask __m, char_type __c) const
```



## Dev notes

### Navigating cmake

ack is useful for looking around for cmake stuff, e.g.

    ack --type=cmake '\bCOMPILER_RT_USE_' ~/tmp/src/llvm


### Core dumps on Ubuntu

Enable saving of core dumps on ubuntu:

```sh
sudo systemctl enable apport.service
sudo service apport start
mkdir -p ~/.config/apport
cat << END >> ~/.config/apport/settings
[main]
unpackaged=true
END
```

Now, when a process crashes:

```sh
rm -rf /tmp/crash && mkdir /tmp/crash
apport-unpack /var/crash/_path_to_program.1000.crash /tmp/crash
ls -l /tmp/crash
(cd /tmp/crash && tar czf ../some-core-dump.tar.gz .)
```


### macOS code signing

macOS on aarch64/arm64 is a pretty hostile dev environment where code signing is required.

Notes from around the world wild web:

- https://github.com/golang/go/issues/42684 "cmd/go: macOS on arm64 requires codesigning"
- https://github.com/ziglang/zig/issues/7103 "stage2: code signing in self-hosted MachO linker (arm64)"
- https://apple.stackexchange.com/a/317002 "What are the restrictions of ad-hoc code signing?"
- https://developer.apple.com/forums/thread/130313 "executable is killed after codesign"

Tools & utilities:

- https://github.com/mitchellh/gon "Sign, notarize, and package macOS CLI tools and applications written in any language. Available as both a CLI and a Go library"
- https://github.com/thefloweringash/sigtool "minimal multicall binary providing helpers for working with embedded signatures in Mach-O files"
- https://github.com/kubkon/ZachO "Zig's Mach-O parser"


## Useful resources

- https://llvm.org/docs/HowToCrossCompileLLVM.html#hacks
- https://llvm.org/docs/BuildingADistribution.html
- https://libcxx.llvm.org/BuildingLibcxx.html
- https://libcxx.llvm.org/UsingLibcxx.html#alternate-libcxx
- https://compiler-rt.llvm.org/
- https://github.com/rust-lang/rust/issues/65051
- https://wiki.musl-libc.org/building-llvm.html
- https://fuchsia.googlesource.com/fuchsia/+/master/docs/development/build/toolchain.md
- https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/compilers/llvm/11/llvm/default.nix#L277
- https://git.alpinelinux.org/aports/tree/main/llvm15
- https://git.alpinelinux.org/aports/tree/main/llvm-runtimes
- https://git.alpinelinux.org/aports/tree/main/clang15
- https://github.com/Homebrew/homebrew-core/blob/master/Formula/llvm.rb
- [llvm-dev mailing list: "Building LLVM with LLVM with no dependence on GCC"](https://lists.llvm.org/pipermail/llvm-dev/2019-September/135199.html)
- https://libc.llvm.org/full_host_build.html

