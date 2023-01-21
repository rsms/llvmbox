This is an attempt to build fully static, self-contained LLVM tools and libraries.

## Goal

- static libries
  - libc++ (libc++.a, libc++abi.a, libunwind.a)
  - compiler-rt (clang_rt.crtbegin.o, clang_rt.crtend.o, libclang_rt.\*.a)
  - llvm IR, opt etc libs (libLLVMPasses.a, ...)
  - clang libs (libLLVMLibDriver.a, ...)
  - lld libs (libLLVMLinker.a, ...)
- statically-linked tools, linked with the above static libaries:
  - clang
  - lld
  - llvm-ar
  - llvm-ranlib
  - llvm-objdump

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

# build stage1 compiler
bash 010-llvm-source-stage1.sh &&
bash 010-zlib-stage1.sh &&
bash 019-llvm-stage1.sh

# build sysroot (some scripts are no-op on non-linux)
bash 020-sysroot.sh &&
bash 021-linux-headers.sh &&
bash 022-musl-libc.sh

# test stage1 compiler
bash 023-test-llvm-stage1.sh

# build packages for stage2 in sysroot
bash 023-musl-fts.sh &&
bash 023-xc.sh &&
bash 023-zlib.sh &&
bash 023-zstd.sh &&
bash 024-libxml2.sh &&
bash 025-xar.sh

# build stage2 compiler
bash 030-llvm-source-stage2.sh
bash 050-llvm-stage2.sh

# test stage2 compiler
bash 090-test-hello.sh

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
- macOS 10.15 x86_64


If you have a lot of RAM, it is usually much faster to build in a ramfs:

- Linux: `export LLVMBOX_BUILD_DIR=/dev/shm`
- Linux with tmpfs: `mkdir -p ~/tmp && sudo mount -t tmpfs -o size=16G tmpfs ~/tmp && export LLVMBOX_BUILD_DIR=$HOME/tmp`
- macOS: `utils/macos-tmpfs.sh ~/tmp && export LLVMBOX_BUILD_DIR=$HOME/tmp`


Define your build directory

```
export LLVMBOX_BUILD_DIR=build
```

Execute the first section of build steps:

```
for f in $(echo 01*.sh | sort); do bash $f; done
```

Now, there are a few alternatives:


### Alternative 1: custom build scripts

```
for f in $(echo 02*.sh | sort); do bash $f; done
```

Succeeds on macOS


### Alternative 2: "stage2" build

Alternative 1: "stage2" build. This is supposed to be the "correct" way to build an llvm distribution but after about 20 hours of trying to make it work on either macOS and Ubuntu, I have doubts.

```
bash stage2.sh
```


Linux builds passes stage1 but fails stage2, suffering from high memory usage; linker is OOM killed:

```
clang++: error: unable to execute command: Killed
clang++: error: linker command failed due to signal (use -v to see invocation)
```

macOS builds passes stage1 but fails stage2 with libc++ link errors like these:

```
ld64.lld: error: undefined symbol: std::__2::generic_category()
>>> referenced by /tmp/lto.tmp:(symbol std::__2::make_error_code[abi:v15007](std::__2::errc)+0x10)
```

If the linker gets OOM killed, try some of the following ideas:

- set LLVMBOX_LTO_JOBS=N, e.g. `LLVMBOX_LTO_JOBS=2 bash stage2.sh`
- allocate more swap space (if you use zfs, see `utils/linux-swap-zfs.sh`)
- disable LTO: `BOOTSTRAP_LLVM_ENABLE_LTO` in stage1.cmake, `LLVM_ENABLE_LTO` in stage2.cmake (must do a full complete clean rebuild after changing these)



----

## Experiment: build with bazel

```
cd experiments/bazel
bash build-llvm-bazel.sh
```

Uses bazel to build llvm in a sandbox. Build works on linux and mac, but produces invalid results that link to shared libraries on the build host. There seem to be no way of building a "stage2" with LLVM's bazel workspace (see experiments/bazel/targets.txt)


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
  -isystem $LLVMBOX_MUSL/include \
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
  -nostdinc++ -isystem $LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1 \
  -I$LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1 \
  -I$(echo $LLVMBOX_BUILD_DIR/llvm-host/include/$(uname -m)-unknown-linux-*)/c++/v1 \
  -L$(echo $LLVMBOX_BUILD_DIR/llvm-host/lib/$(uname -m)-unknown-linux-*) \
  -nostdlib++ -L$LLVMBOX_BUILD_DIR/llvm-host/lib \
  -lc++ \
  \
  -isystem $LLVMBOX_MUSL/include \
  -nostartfiles $LLVMBOX_MUSL/lib/crt1.o \
  -nostdlib -L$LLVMBOX_MUSL/lib -lc \
  test/hello.cc -o test/hello_cc

LLVMBOX_BUILD_DIR/llvm-host/include/c++/v1/__locale:572:13: error: unknown type name 'mask'
    bool is(mask __m, char_type __c) const
```



## Issues


Linux llvm host build _"warning: Using 'NAME' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking"_

    [567/3170] Linking CXX executable bin/llvm-config
    /usr/bin/ld: lib/libLLVMSupport.a(Path.cpp.o): in function `llvm::sys::fs::expandTildeExpr(llvm::SmallVectorImpl<char>&)':
    Path.cpp:(.text._ZN4llvm3sys2fsL15expandTildeExprERNS_15SmallVectorImplIcEE+0x1a6): warning: Using 'getpwnam' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking



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



## Useful resources

- https://llvm.org/docs/HowToCrossCompileLLVM.html#hacks
- https://llvm.org/docs/BuildingADistribution.html
- https://libcxx.llvm.org/BuildingLibcxx.html
- https://libcxx.llvm.org/UsingLibcxx.html#alternate-libcxx
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

