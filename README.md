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
- macOS: `utils/macos-tmpfs.sh build && export LLVMBOX_BUILD_DIR=build`


Define your build directory

```
export LLVMBOX_BUILD_DIR=build
```

Execute the first section of build steps:

```
for f in $(echo 01*.sh | sort); do bash $f; done
```

Now, there are a few alternatives:

### Alternative 1: "stage2" build

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

If the linker gets OOM killed, set LLVMBOX_LTO_JOBS=N, e.g.

```
LLVMBOX_LTO_JOBS=2 bash stage2.sh
```


### Alternative 2: custom build scripts per platform

Linux:

```
for f in $(echo 0*-linux-*.sh | sort); do bash $f; done
```

macOS:

```
for f in $(echo 0*-mac-*.sh | sort); do bash $f; done
```

macOS build currently fails during compiler-rt:

```
[2299/10112] Building ASM object projects/compiler-rt/lib/builtins/CMakeFiles/clang_rt.builtins_i386_osx.dir/i386/ashldi3.S.o
FAILED: projects/compiler-rt/lib/builtins/CMakeFiles/clang_rt.builtins_i386_osx.dir/i386/ashldi3.S.o
/usr/bin/clang -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -I/Users/rsms/tmp/llvm-macos-build/projects/compiler-rt/lib/builtins -I/Users/rsms/tmp/src/llvm/compiler-rt/lib/builtins -I/Users/rsms/tmp/llvm-macos-build/include -I/Users/rsms/tmp/src/llvm/llvm/include -Os -DNDEBUG -arch i386 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX11.1.sdk -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX11.1.sdk -mmacosx-version-min=10.5 -fPIC -O3 -fvisibility=hidden -DVISIBILITY_HIDDEN -Wall -fomit-frame-pointer -arch i386 -target i386-apple-macos10.5 -darwin-target-variant i386-apple-ios13.1-macabi -MD -MT projects/compiler-rt/lib/builtins/CMakeFiles/clang_rt.builtins_i386_osx.dir/i386/ashldi3.S.o -MF projects/compiler-rt/lib/builtins/CMakeFiles/clang_rt.builtins_i386_osx.dir/i386/ashldi3.S.o.d -o projects/compiler-rt/lib/builtins/CMakeFiles/clang_rt.builtins_i386_osx.dir/i386/ashldi3.S.o -c /Users/rsms/tmp/src/llvm/compiler-rt/lib/builtins/i386/ashldi3.S
clang: error: no such file or directory: 'i386-apple-ios13.1-macabi'
```


----

## Experiment: build with bazel

```
cd experiments/bazel
bash build-llvm-bazel.sh
```

Uses bazel to build llvm in a sandbox. Build works on linux and mac, but produces invalid results that link to shared libraries on the build host. There seem to be no way of building a "stage2" with LLVM's bazel workspace (see experiments/bazel/targets.txt)


----

## Test

```sh
# bash test/test.sh <compiler-root>
bash test/test.sh $LLVMBOX_BUILD_DIR/llvm-host
```

### cc and c++ wrappers

There are wrapper scripts to help with testing, which invokes clang with the appropriate flags:

```
LLVM_ROOT=/dev/shm/llvm-host utils/cc test/hello.c -o test/hello_c
LLVM_ROOT=/dev/shm/llvm-host utils/c++ test/hello.cc -o test/hello_cc
```



## Current status


- macOS 10.15 x86_64 build host: dist build FAILING
- Ubuntu x86_64 build host: dist build FAILING


## Issues


Linux llvm host build _"warning: Using 'NAME' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking"_

    [567/3170] Linking CXX executable bin/llvm-config
    /usr/bin/ld: lib/libLLVMSupport.a(Path.cpp.o): in function `llvm::sys::fs::expandTildeExpr(llvm::SmallVectorImpl<char>&)':
    Path.cpp:(.text._ZN4llvm3sys2fsL15expandTildeExprERNS_15SmallVectorImplIcEE+0x1a6): warning: Using 'getpwnam' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking



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
