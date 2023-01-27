#include "llvm/Support/FileSystem.h"

extern "C" char* LLVMGetMainExecutable(const char* argv0) {
  // This just needs to be some symbol in the binary; C++ doesn't
  // allow taking the address of ::main however.
  void* P = (void*)(intptr_t)LLVMGetMainExecutable;
  return strdup(llvm::sys::fs::getMainExecutable(argv0, P).c_str());
}
