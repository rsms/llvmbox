/*
When compiling llvm, we got the following error:

out/llvm-stage1/bin/clang++
  --sysroot=/Users/rsms/src/llvm/out/sysroot/x86_64-macos-10
  -DGTEST_HAS_RTTI=0
  -D__STDC_CONSTANT_MACROS
  -D__STDC_FORMAT_MACROS
  -D__STDC_LIMIT_MACROS
  -I/Users/rsms/tmp/llvm-stage2/lib/Support
  -I/Users/rsms/src/llvm/out/src/llvm/llvm/lib/Support
  -I/Users/rsms/tmp/llvm-stage2/include
  -I/Users/rsms/src/llvm/out/src/llvm/llvm/include
  -isystem /Users/rsms/src/llvm/out/zlib-x86_64-macos-10/include
  -isystem /Users/rsms/src/llvm/out/zstd-x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/sysroot/x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/xar-x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/xc-x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/openssl-x86_64-macos-10/include
  -nostdinc++
  -I/Users/rsms/src/llvm/out/libcxx-stage2/include/c++/v1
  -I/Users/rsms/src/llvm/out/sysroot/x86_64-macos-10/include
  -DTARGET_OS_EMBEDDED=0
  -DTARGET_OS_IPHONE=0
  -I/Users/rsms/src/llvm/out/xar-x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/xc-x86_64-macos-10/include
  -I/Users/rsms/src/llvm/out/openssl-x86_64-macos-10/include
  -nostdinc++
  -I/Users/rsms/src/llvm/out/libcxx-stage2/include/c++/v1
  -I/Users/rsms/src/llvm/out/sysroot/x86_64-macos-10/include
  -DTARGET_OS_EMBEDDED=0
  -DTARGET_OS_IPHONE=0
  -fvisibility-inlines-hidden
  -pedantic
  -fdiagnostics-color
  -Os
  -DNDEBUG
  -isysroot /Users/rsms/src/llvm/out/sysroot/x86_64-macos-10
  -mmacosx-version-min=10.15
  -std=c++14
  -fno-exceptions
  -fno-rtti
  -MD
  -MT lib/Support/CMakeFiles/LLVMSupport.dir/ManagedStatic.cpp.o
  -MF lib/Support/CMakeFiles/LLVMSupport.dir/ManagedStatic.cpp.o.d
  -o lib/Support/CMakeFiles/LLVMSupport.dir/ManagedStatic.cpp.o
  -c /Users/rsms/src/llvm/out/src/llvm/llvm/lib/Support/ManagedStatic.cpp

In file included from out/src/llvm/llvm/lib/Support/ManagedStatic.cpp:15:
In file included from out/src/llvm/llvm/include/llvm/Support/Threading.h:17:
In file included from out/src/llvm/llvm/include/llvm/ADT/BitVector.h:17:
In file included from out/src/llvm/llvm/include/llvm/ADT/ArrayRef.h:12:
In file included from out/src/llvm/llvm/include/llvm/ADT/Hashing.h:50:
In file included from out/src/llvm/llvm/include/llvm/Support/type_traits.h:18:
In file included from out/libcxx-stage2/include/c++/v1/utility:242:
In file included from out/libcxx-stage2/include/c++/v1/__utility/unreachable.h:13:
out/libcxx-stage2/include/c++/v1/cstdlib:123:9:
  error: target of using declaration conflicts with declaration already in scope
  using ::abs _LIBCPP_USING_IF_EXISTS;
          ^
out/sysroot/x86_64-macos-10/include/stdlib.h:132:6:
  note: target of using declaration
  int      abs(int) __pure2;
           ^
out/libcxx-stage2/include/c++/v1/cmath:339:1:
  note: conflicting declaration
  using ::abs _LIBCPP_USING_IF_EXISTS;
  ^

*/
#include <random>
#include <utility>
int main() {
  return 0;
}
