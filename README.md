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

Host systems: (checked = known to work, unchecked = may work)

- [x] Ubuntu 20 x86_64
- [x] macOS 10.15 x86_64
- [ ] macOS 12 arm64


```
bash build.sh ./mybuild
```

If you have a lot of RAM, it is usually much faster to build in a ramfs:

Linux:

```
bash build.sh /dev/shm/llvm
```

macOS:

```
./macos-tmpfs.sh build && bash build.sh build
```



## Test

```
bash test.sh
```



## Issues


Linux llvm host build _"warning: Using 'NAME' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking"_

    [567/3170] Linking CXX executable bin/llvm-config
    /usr/bin/ld: lib/libLLVMSupport.a(Path.cpp.o): in function `llvm::sys::fs::expandTildeExpr(llvm::SmallVectorImpl<char>&)':
    Path.cpp:(.text._ZN4llvm3sys2fsL15expandTildeExprERNS_15SmallVectorImplIcEE+0x1a6): warning: Using 'getpwnam' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking

