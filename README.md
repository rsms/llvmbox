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
- macOS: `./macos-tmpfs.sh build && export LLVMBOX_BUILD_DIR=build`


You can build everything using `build.sh` or running each step separately,
the latter is useful when a step needs adjustments and you don't want to rebuild the
previous steps:

```
export LLVMBOX_BUILD_DIR=build
bash build.sh
```

```
export LLVMBOX_BUILD_DIR=build
bash 010-llvm-source.sh
bash 011-update-myclang-source.sh
bash 020-zlib-host.sh
bash 021-llvm-host.sh
bash 030-zlib-dist.sh
bash 031-llvm-dist.sh
```



## Test

```sh
# bash test/test.sh <compiler-root>
bash test/test.sh $LLVMBOX_BUILD_DIR/llvm-host
```

### cc and c++ wrappers

There are wrapper scripts to help with testing, which invokes clang with the appropriate flags:

```
LLVM_ROOT=/dev/shm/llvm-host ./cc test/hello.c -o test/hello_c
LLVM_ROOT=/dev/shm/llvm-host ./c++ test/hello.cc -o test/hello_cc
```



## Current status


### macOS 10.15 x86_64 build host: dist build FAILING

```
$ bash 031-llvm-dist.sh
...
In file included from /Users/rsms/tmp/llvm-src/compiler-rt/lib/builtins/arm/fp_mode.c:9:
In file included from /Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include/stdint.h:53:
In file included from /Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include/sys/_types/_intptr_t.h:30:
/Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include/machine/types.h:37:2: error: architecture not supported
#error architecture not supported
 ^
...
```


### Ubuntu x86_64 build host: dist build FAILING

```
$ bash 031-llvm-dist.sh
...
[906/4703] Linking CXX shared module lib/LLVMHello.so
FAILED: lib/LLVMHello.so
: && /dev/shm/llvm-host/bin/clang++ -nostdinc++ -isystem /dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/x86_64-unknown-linux-gnu/c++/v1 --target=x86_64-linux-gnu -I/dev/shm/zlib-x86_64-linux-gnu/include -isystem /dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/x86_64-unknown-linux-gnu/c++/v1 --target=x86_64-linux-gnu -I/dev/shm/zlib-x86_64-linux-gnu/include -fPIC -nostdinc++ -isystem /dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/c++/v1 -I/dev/shm/llvm-host/include/x86_64-unknown-linux-gnu/c++/v1 --target=x86_64-linux-gnu -I/dev/shm/zlib-x86_64-linux-gnu/include -fPIC -fno-semantic-interposition -fvisibility-inlines-hidden -Werror=date-time -Werror=unguarded-availability-new -Wall -Wextra -Wno-unused-parameter -Wwrite-strings -Wcast-qual -Wmissing-field-initializers -pedantic -Wno-long-long -Wc++98-compat-extra-semi -Wimplicit-fallthrough -Wcovered-switch-default -Wno-noexcept-type -Wnon-virtual-dtor -Wdelete-non-virtual-dtor -Wsuggest-override -Wstring-conversion -Wmisleading-indentation -fdiagnostics-color -ffunction-sections -fdata-sections -Os -DNDEBUG  -nostdlib++ -lc++ -lc++abi -static -fuse-ld=lld -L/dev/shm/llvm-host/lib -L/dev/shm/llvm-host/lib/x86_64-unknown-linux-gnu -L/dev/shm/zlib-x86_64-linux-gnu/lib -L/dev/shm/llvm-host/lib/x86_64-linux-gnu -Wl,-z,nodelete -Wl,--color-diagnostics   -Wl,--gc-sections  -Wl,--version-script,"/dev/shm/llvm-dist-build/lib/Transforms/Hello/LLVMHello.exports" -shared  -o lib/LLVMHello.so lib/Transforms/Hello/CMakeFiles/LLVMHello.dir/Hello.cpp.o  -Wl,-rpath,"\$ORIGIN/../lib" && :
clang-15: warning: argument unused during compilation: '-nostdinc++' [-Wunused-command-line-argument]
clang-15: warning: argument unused during compilation: '-nostdinc++' [-Wunused-command-line-argument]
ld.lld: error: relocation R_X86_64_TPOFF32 against tcache cannot be used with -shared
>>> defined in /lib/x86_64-linux-gnu/libc.a(malloc.o)
>>> referenced by malloc.o:(_int_free) in archive /lib/x86_64-linux-gnu/libc.a

ld.lld: error: relocation R_X86_64_TPOFF32 against tcache cannot be used with -shared
>>> defined in /lib/x86_64-linux-gnu/libc.a(malloc.o)
>>> referenced by malloc.o:(_int_free) in archive /lib/x86_64-linux-gnu/libc.a

ld.lld: error: relocation R_X86_64_TPOFF32 against tcache cannot be used with -shared
>>> defined in /lib/x86_64-linux-gnu/libc.a(malloc.o)
>>> referenced by malloc.o:(_int_malloc) in archive /lib/x86_64-linux-gnu/libc.a
...
```



## Issues


Linux llvm host build _"warning: Using 'NAME' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking"_

    [567/3170] Linking CXX executable bin/llvm-config
    /usr/bin/ld: lib/libLLVMSupport.a(Path.cpp.o): in function `llvm::sys::fs::expandTildeExpr(llvm::SmallVectorImpl<char>&)':
    Path.cpp:(.text._ZN4llvm3sys2fsL15expandTildeExprERNS_15SmallVectorImplIcEE+0x1a6): warning: Using 'getpwnam' in statically linked applications requires at runtime the shared libraries from the glibc version used for linking

