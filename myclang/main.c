// SPDX-License-Identifier: Apache-2.0
#include <stdio.h>
#include <string.h> // strcmp
#include <err.h>


extern int clang_main(int argc, char*const* argv); // driver.cc


int main(int argc, char* argv[]) {
  if (argc < 2) {
    fprintf(stderr, "%s: missing <command>\n", argv[0]);
    return 1;
  }

  // clang "cc" may spawn itself in a new process
  if (strcmp(argv[1], "-cc1") == 0 || strcmp(argv[1], "-cc1as") == 0)
    return clang_main(argc, argv);

  if (strcmp(argv[1], "as" == 0)) {
    argv[1] = "-cc1as";
    return clang_main(argc, argv);
  }

  if (strcmp(argv[1], "cc") == 0 || strcmp(argv[1], "c++") == 0) {
    argc--, argv++; // shave away argv[0]
    return clang_main(argc, argv);
  }

  printf(
    "usage: %s <command>\n"
    "commands:\n"
    "  cc   C compiler (clang)\n"
    "  c++  C++ compiler (clang++)\n"
    "  ar   Archiver (llvm-ar)\n"
  );
  return 0;
}
