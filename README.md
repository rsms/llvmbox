llvmbox is a highly "portable" distribution of the LLVM tools and development libraries, without external dependencies.

Simply unpack the tar file and you have a fully-functional compiler toolchain that is fully self-contained (does not need libc or even a dynamic linker to be present on your system.)

Features:

- Self-contained; install with wget/curl
- Runs on any Linux system ("Linux-distro less" — there's no "gnu", "musl" or "ulibc" variants; all it needs is linux syscall)
- Contains its own sysroot
  - Does not need libc nor libc++ headers to be installed on your system
  - On Linux, does not need linux headers to be installed on your system
  - On macOS, does not need Xcode or Command Line Developer Tools
- LLVM development libraries in separate installable archive
  - Separate distribution reduces file size for when you just need the toolchain.
  - Includes ThinLTO libraries in lib-lto in addition to precompiled target code libraries, enabling you to build 100% LTOd products. This includes libc and libc++, not just LLVM libs.
  - Includes libraries for building your own custom clang and lld tools
  - Includes a development time-optimized library `liball_llvm_clang_lld.a` which contains all llvm libs, clang libs, lld libs and dependencies. It allows building your own clang or lld with link speeds in the 100s of milliseconds.

Supported systems:

  - Linux: x86_64 (aarch64: work in progress)
  - macOS: minimum OS 10.15, x86_64 (arm64: work in progress)
  - Windows: NOT YET SUPPORTED — [contributions welcome!](CONTRIBUTING.md)

## Usage

```sh
# download & install in current directory
wget -qO- https:// | tar xz

# create example C++ source
cat << EXAMPLE > hello.cc
#include <iostream>
int main(int argc, const char** argv) {
  std::cout << "hello from " << argv[0] << "\n";
  return 0;
}
EXAMPLE

# compile
[ $(uname -s) = Linux ] && LDFLAGS=-static
./llvmbox-VERSION/bin/clang++ $LDFLAGS hello.cc -o hello

# run example
./hello
```


## Using LLVM libraries

LLVM libraries are distributed in a separate archive "llvmbox-dev." Its directory tree can either be merged into the toolchain ("llvmbox") tree, or placed anywhere, given appropriate compiler and linker flags are used.

```sh
# download & install in current directory
wget -qO- https:// | tar xz

# fetch example program
wget https://github.com/rsms/llvmbox/blob/954ee63a9c82c4f2dca2dd319496f1cfa5d7d06d/test/hello-llvm.c

# compile
./llvmbox-VERSION/bin/clang $CFLAGS \
  $(./llvmbox-dev-VERSION/bin/llvm-config --cflags) \
  -c hello-llvm.c -o hello-llvm.o

# link
LDFLAGS="$LDFLAGS -Lllvmbox-dev-VERSION/lib"
[ $(uname -s) = Linux ] && LDFLAGS="$LDFLAGS -static"
./llvmbox-VERSION/bin/clang++ $LDFLAGS \
  $(./llvmbox-dev-VERSION/bin/llvm-config --ldflags --system-libs --libs core native) \
  hello-llvm.o -o hello-llvm

# run example
./hello-llvm
```


If you are interested in building your own C/C++ compiler based on clang & lld, have a look at the [`myclang`](myclang/) example.


### Building with LTO libs

[ThinLTO](https://clang.llvm.org/docs/ThinLTO.html) performs whole-program optimization during the linker stage. This can in some cases greatly improve performance and often leads to slightly smaller binaries. The cost is longer link times. llvmbox ships with both regular machine code libraries as well as ThinLTO libraries. During development you can link with regular libraries with millisecond-fast link times and for production builds you can link with LTO for improved runtime performance.

Continuing off of our "hello-llvm" example above, let's change compiler and linker flags. `-flto=thin` enables creation of LTO objects. We need to set library search path to the location of the LTO libraries: `lib-lto`. (The `lib` directory of llvmbox contains "regular" libraries with machine code.)

```sh
CFLAGS="$CFLAGS -flto=thin"
LDFLAGS="$LDFLAGS -Lllvmbox-dev-VERSION/lib-lto"

./llvmbox-VERSION/bin/clang \
  $(./llvmbox-dev-VERSION/bin/llvm-config --cflags) \
  -flto=thin \
  -c hello-llvm.c -o hello-llvm.o

./llvmbox-VERSION/bin/clang++ $LDFLAGS \
  $(./llvmbox-dev-VERSION/bin/llvm-config --system-libs --libs core native) \
  hello-llvm.o -o hello-llvm
```

Turn on ThinLTO cache to enable fast incremental compilation:

```sh
mkdir -p lto-cache
case "$(uname -s)" in
  Linux)  LDFLAGS="$LDFLAGS -Wl,--thinlto-cache-dir=$PWD/lto-cache" ;;
  Darwin) LDFLAGS="$LDFLAGS -Wl,-cache_path_lto,$PWD/lto-cache" ;;
esac
```

Now, recompiling after making a small change to a source file is much faster.
