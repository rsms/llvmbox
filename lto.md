# Notes on LTO

## Time and space

```
without LTO, linux x86_64, -Os (libc and libc++ are precompiled MC)
  SOURCE     OUT SIZE   CTIME/STRIPPED
  hello.c      24,528   0.030s
  hello.c      18,384   stripped
  hello.cc  1,114,416   0.622s
  hello.cc    775,568   stripped

with LTO, linux x86_64, -O2 --lto-O2 (libc and libc++ are LLVM BC)
  SOURCE     OUT SIZE   CTIME/STRIPPED
  hello.c     135,144   0.231s (hot LTO cache)
  hello.c     112,592   stripped
  hello.cc    708,880   0.848s (hot LTO cache)
  hello.cc    522,984   stripped

with LTO, linux x86_64, -Os --lto-O2 (libc and libc++ are LLVM BC)
  SOURCE     OUT SIZE   CTIME/STRIPPED
  hello.c     135,128   0.229s (hot LTO cache)
  hello.c     112,576   stripped
  hello.cc    708,848   0.857s (hot LTO cache)
  hello.cc    522,952   stripped

with LTO, linux x86_64, -O0 --lto-O0 (libc and libc++ are LLVM BC)
  SOURCE     OUT SIZE   CTIME/STRIPPED
  hello.c     127,184   0.230s (hot LTO cache)
  hello.c     104,288   stripped
  hello.cc    715,496   0.851s (hot LTO cache)
  hello.cc    516,312   stripped
```

These tests were done like this:

```sh
LLVMBOX_ENABLE_LTO=0 \
LLVMBOX_BUILD_DIR=$LLVMBOX_BUILD_DIR/nolto \
LLVMBOX_DESTDIR=out/llvmbox-nolto (./build.sh 02 && ./build.sh 03)

LLVMBOX_ENABLE_LTO=1 ./build.sh 02
LLVMBOX_ENABLE_LTO=1 ./build.sh 03

CFLAGS=-Os bash 035-test-hello.sh out/llvmbox-nolto
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*
out/llvmbox/bin/strip "$LLVMBOX_BUILD_DIR/hello_c"*
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*

CFLAGS=-O2 bash 035-test-hello.sh out/llvmbox
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*
out/llvmbox/bin/strip "$LLVMBOX_BUILD_DIR/hello_c"*
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*

CFLAGS=-Os bash 035-test-hello.sh out/llvmbox
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*
out/llvmbox/bin/strip "$LLVMBOX_BUILD_DIR/hello_c"*
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*

CFLAGS=-O0 LDFLAGS=-Wl,--lto-O0 bash 035-test-hello.sh out/llvmbox
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*
out/llvmbox/bin/strip "$LLVMBOX_BUILD_DIR/hello_c"*
ls -l "$LLVMBOX_BUILD_DIR/hello_c"*
```

## Other observations

libc++ built WITHOUT ThinLTO, compiling without -flto=thin

    time out/llvmbox-15.0.7-x86_64-linux/bin/clang++ -O2 -Wl,-s -flto=thin -static \
      test/hello.cc -o out/hello
    real 0m0.614s, user 0m0.558s, sys 0m0.077s
    l out/hello | cut -d' ' -f5
    758K

libc++ built with ThinLTO, compiling with -flto=thin

    time out/llvmbox-15.0.7-x86_64-linux/bin/clang++ -O2 -Wl,-s -flto=thin -static \
      test/hello.cc -o out/hello
    real 0m4.253s, user 0m7.680s, sys 0m10.432s
    l out/hello | cut -d' ' -f5
    485K

libc++ built with ThinLTO, compiling WITHOUT -flto=thin

    time out/llvmbox-15.0.7-x86_64-linux/bin/clang++ -O2 -Wl,-s -static \
      test/hello.cc -o out/hello
    real 0m4.161s, user 0m7.410s, sys 0m9.677s
    l out/hello | cut -d' ' -f5
    486K

using ThinLTO cache, it is much faster:

    rm -rf out/ltocache && mkdir out/ltocache
    time out/llvmbox-15.0.7-x86_64-linux/bin/clang++ -O2 -flto=thin \
      -Wl,--thinlto-cache-dir=out/ltocache -static test/hello.cc -o out/hello
    real 0m4.253s  <-- first run; no cache

    time out/llvmbox-15.0.7-x86_64-linux/bin/clang++ -O2 -flto=thin \
      -Wl,--thinlto-cache-dir=out/ltocache -static test/hello.cc -o out/hello
    real 0m0.700s  <-- cache used


To quickly rebuild & test libc++ with or without ThinLTO, here's a shortcut:

1. edit 031-llvm-runtimes.sh and remove/add the -flto=thin flags
2. rebuild libc++ and copy into sysroot:
   `rm -rf ~/tmp/llvm-runtimes/ && bash 031-llvm-runtimes.sh &&
    cp out/libcxx-stage2/lib/lib*.a \
      out/llvmbox-15.0.7-x86_64-linux/sysroot/x86_64-linux/lib/`


## See also

- https://clang.llvm.org/docs/ThinLTO.html
- https://blog.llvm.org/2016/06/thinlto-scalable-and-incremental-lto.html
