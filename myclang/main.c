// SPDX-License-Identifier: Apache-2.0
#include <libgen.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "clang/Basic/Version.inc" // CLANG_VERSION_STRING

static char* myclang;

// driver.cc
extern int clang_main(int argc, char*const* argv);

// lld.cc
bool LLDLinkCOFF(int argc, char*const* argv);
bool LLDLinkELF(int argc, char*const* argv);
bool LLDLinkMachO(int argc, char*const* argv);
bool LLDLinkWasm(int argc, char*const* argv);

// llvm-utils.cc
char* LLVMGetMainExecutable(const char* argv0);

static char* mkflag(
  const char* flag, char glue, const char* value1, const char* value2)
{
  char* s = malloc(strlen(flag) + strlen(value1) + (value2 ? strlen(value2) : 0) + 2);
  if (!s)
    return NULL;
  int i = 0;
  memcpy(&s[i], flag, strlen(flag));
  i += strlen(flag);
  if (glue)
    s[i++] = glue;
  memcpy(&s[i], value1, strlen(value1));
  i += strlen(value1);
  if (value2) {
    memcpy(&s[i], value2, strlen(value2));
    i += strlen(value2);
  }
  s[i] = 0;
  return s;
}

static int cc_main(int argc, char* argv[]) {
  char* i_include = mkflag("-isystem", 0, MYCLANG_SYSROOT, "/include");
  char* resource_dir = mkflag("-resource-dir", '=', MYCLANG_SYSROOT,
    "/../../lib/clang/" CLANG_VERSION_STRING);

  if (!i_include || !resource_dir)
    return 2;

  const char* default_args[] = {
    "-flto",
    "--sysroot=" MYCLANG_SYSROOT,
    "-fuse-ld=lld",
    i_include,
    resource_dir,
    #if __APPLE__
      "-Wl,-platform_version,macos,10.15,10.15",
      "-DTARGET_OS_EMBEDDED",
      "-Wno-nullability-completeness",
    #endif
  };
  int ndefault_args = (int)(sizeof(default_args)/sizeof(default_args[0]));

  int argc2 = ndefault_args + argc;
  char** argv2 = (char**)malloc(sizeof(void*) * argc2);
  if (argv2 == NULL)
    return 2;
  argv2[0] = argv[0];
  memcpy(argv2 + 1, default_args, ndefault_args * sizeof(void*));
  memcpy(argv2 + 1 + ndefault_args, argv+1, (argc-1) * sizeof(void*));

  // if -v is set, print invocation
  bool has_v = false;
  for (int i = 1; i < argc2; i++)
    has_v |= strcmp(argv2[i], "-v") == 0;
  if (has_v) {
    printf("myclang invoking\n");
    for (int i = 0; i < argc2; i++)
      printf("  \"%s\"\n", argv2[i]);
  }

  return clang_main(argc2, argv2);
}

int main(int argc, char* argv[]) {
  const char* progname = strrchr(argv[0], '/');
  progname = progname ? progname + 1 : argv[0];
  bool is_multicall = strcmp(progname, "myclang") != 0;

  const char* cmd = is_multicall ? progname : argv[1] ? argv[1] : "";
  unsigned long cmdlen = strlen(cmd);
  #define ISCMD(s) (cmdlen == strlen(s) && memcmp(cmd, (s), cmdlen) == 0)

  myclang = LLVMGetMainExecutable(argv[0]);

  // clang "cc" may spawn itself in a new process
  if (ISCMD("-cc1") || ISCMD("-cc1as"))
    return clang_main(argc, argv);

  if (ISCMD("as")) {
    argv[1] = "-cc1as";
    return clang_main(argc, argv);
  }

  // shave away argv[0] ("myclang")
  if (!is_multicall)
    argc--, argv++;

  if (ISCMD("cc")) {
    argv[0] = "clang";
    return cc_main(argc, argv);
  }

  if (ISCMD("c++")) {
    argv[0] = "clang++";
    return cc_main(argc, argv);
  }

  if (ISCMD("ld64.lld"))
    return LLDLinkMachO(argc, argv) ? 0 : 1;

  if (ISCMD("ld.lld"))
    return LLDLinkELF(argc, argv) ? 0 : 1;

  if (ISCMD("lld-link"))
    return LLDLinkCOFF(argc, argv) ? 0 : 1;

  if (ISCMD("wasm-ld"))
    return LLDLinkWasm(argc, argv) ? 0 : 1;

  printf(
    "usage: %s <command>\n"
    "commands:\n"
    "  cc        C compiler (clang)\n"
    "  c++       C++ compiler (clang++)\n"
    "  ar        Archiver (llvm-ar)\n"
    "  ld.lld    Mach-o linker\n"
    "  ld64.lld  ELF linker\n"
    "  lld-link  COFF linker\n"
    "  wasm-ld   WASM linker\n"
  , progname);
  return 0;
}
