// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"

#define CHECK(expr) if (!(expr)) errx(1, #expr)
#define STR1(x) #x
#define STR(x) STR1(x)


const char* target = "";
const char* var_prefix = "";
usize var_prefix_len = 0;
char llvmbox_dir[PATH_MAX];


int main(int argc, char* argv[]) {
  opterr = 0; // don't print built-in error messages
  for (int c; (c = getopt(argc, argv, "t:h")) != -1; ) switch (c) {
    case 'h': printf(
      "Print llvmbox configuration.\n"
      "usage: %s [options] [<var-prefix>]\n"
      "options:\n"
      "  -h  Print help on stdout and exit\n"
      // "  -t <target>  Include target-specific information\n"
      // "<target>\n"
      // "  [arch-]sys[.sysver], e.g. aarch64-linux, x86_64-macos.10, linux\n"
      , argv[0]);
      exit(0);
      break;
    case 't': target = optarg; break;
    case '?':
      warnx("unrecognized option -%c", optopt);
      return 1;
  }
  if (argc - optind > 0) {
    var_prefix = argv[optind];
    var_prefix_len = strlen(var_prefix);
    if (argc - optind > 1)
      errx(1, "unexpected extra argument");
  }

  // resolve path to executable
  const char* exe_path = get_exe_path(argv[0]);
  CHECK(exe_path != NULL);

  CHECK(path_join_resolve(llvmbox_dir, exe_path, "../.."));

  #define VAR(name, fmt, args...) \
    if (strncmp(name ":", var_prefix, var_prefix_len) == 0) \
      printf(name ": " fmt "\n", ##args)

  VAR("version",         "%s", STR(LLVM_VERSION) "+" STR(LLVMBOX_VERSION));
  VAR("version.llvmbox", "%s", STR(LLVMBOX_VERSION));
  VAR("version.llvm",    "%s", STR(LLVM_VERSION));
  VAR("dir",             "%s", llvmbox_dir);
  VAR("dir.bin",         "%s/bin", llvmbox_dir);
  VAR("dir.targets",     "%s/targets", llvmbox_dir);

  return 0;
}
