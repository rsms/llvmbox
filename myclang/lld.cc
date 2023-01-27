#include "lld/Common/Driver.h"
#include "lld/Common/ErrorHandler.h"
#include "lld/Common/Memory.h"

static const bool can_exit_early = true;

extern "C" bool LLDLinkCOFF(int argc, char*const*argv) {
  std::vector<const char *> args(argv, argv + argc);
  return lld::coff::link(args, llvm::outs(), llvm::errs(), can_exit_early, false);
}

extern "C" bool LLDLinkELF(int argc, char*const*argv) {
  std::vector<const char *> args(argv, argv + argc);
  return lld::elf::link(args, llvm::outs(), llvm::errs(), can_exit_early, false);
}

extern "C" bool LLDLinkMachO(int argc, char*const*argv) {
  std::vector<const char *> args(argv, argv + argc);
  return lld::macho::link(args, llvm::outs(), llvm::errs(), can_exit_early, false);
}

extern "C" bool LLDLinkWasm(int argc, char*const*argv) {
  std::vector<const char *> args(argv, argv + argc);
  return lld::wasm::link(args, llvm::outs(), llvm::errs(), can_exit_early, false);
}
