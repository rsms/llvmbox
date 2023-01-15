// from llvm/cmake/modules/CheckAtomic.cmake
#include <atomic>
std::atomic<int> x;
std::atomic<short> y;
std::atomic<char> z;
int main() {
  ++z;
  ++y;
  return ++x;
}
