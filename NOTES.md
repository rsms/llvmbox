(Chris) 
On Arch Linux, with the default llvm package installed, step `012-llvm-host.sh` fails because clang does not support std::atomic (?)
Very weird, but if you use gcc: `export CC=/usr/bin/gcc`; `export CXX=/usr/bin/g++` everything works. Also, you need to remove the cmake cache if you accidentally start with llvm/clang instead of gcc...

No idea why it's giving the std::atomic error message:

```
CMake Error at cmake/modules/CheckAtomic.cmake:56 (message):
  Host compiler must support std::atomic!
Call Stack (most recent call first):
  cmake/config-ix.cmake:411 (include)
  CMakeLists.txt:776 (include)
```
