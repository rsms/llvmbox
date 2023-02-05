// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"


void check_dir_args(const char* srcdir, const char* dstdir) {
  // copy_merge is UD if src or dir is inside the other
  char srcdir_abs[PATH_MAX];
  char dstdir_abs[PATH_MAX];
  if (!path_resolve(srcdir_abs, srcdir))
    err(1, "%s", srcdir);
  if (strlen(dstdir) == 0)
    errx(1, "empty <dstdir> argument");
  if (!path_resolve(dstdir_abs, dstdir) && errno != ENOENT)
    err(1, "%s", dstdir);
  // append '/' to avoid false "is inside" detection
  usize srcdir_abs_len = strlen(srcdir_abs);
  if (srcdir_abs_len < PATH_MAX-1) {
    srcdir_abs[srcdir_abs_len] = '/';
    srcdir_abs[srcdir_abs_len + 1] = 0;
  }
  usize dstdir_abs_len = strlen(dstdir_abs);
  if (dstdir_abs_len < PATH_MAX-1) {
    dstdir_abs[dstdir_abs_len] = '/';
    dstdir_abs[dstdir_abs_len + 1] = 0;
  }
  if (strcmp(srcdir_abs, dstdir_abs) == 0)
    errx(1, "<srcdir> and <dstdir> are the same");
  if (strstr(srcdir_abs, dstdir_abs))
    errx(1, "<dstdir> is inside <srcdir>");
  if (strstr(dstdir_abs, srcdir_abs))
    errx(1, "<srcdir> is inside <dstdir>");
}


int main(int argc, char* argv[]) {
  int cm_flags = 0;

  opterr = 0; // don't print built-in error messages
  for (int c; (c = getopt(argc, argv, ":hfv")) != -1; ) switch (c) {
    case 'h': printf(
      "Merges one directory into another.\n"
      "usage: %s [options] <srcdir> <dstdir>\n"
      "Options:\n"
      "  -f  Overwrite files\n"
      "  -v  Verbose; print what is done to stdout\n"
      "  -h  Show help and exit\n"
      "<srcdir> is a directory to copy from.\n"
      "<dstdir> is a directory to merge into.\n"
      "<srcdir> and <dstdir> can be files or symlinks in which case\n"
      "this tool works just like cp -a <srcdir> <dstdir>.\n"
      , argv[0]);
      exit(0);
      break;
    case 'f': cm_flags |= COPY_MERGE_OVERWRITE; break;
    case 'v': cm_flags |= COPY_MERGE_VERBOSE; break;
    case '?':
      warnx("unrecognized option -%c", optopt);
      return 1;
  }

  if (optind == argc)
    errx(1, "missing <srcdir> argument");
  if (argc - optind < 2)
    errx(1, "missing <dstdir> argument");
  if (argc - optind > 2) // probably a mistake; print & die instead of ignoring
    errx(1, "extraneous argument");

  const char* srcdir = argv[optind];
  const char* dstdir = argv[optind+1];

  check_dir_args(srcdir, dstdir);

  if (!copy_merge(srcdir, dstdir, cm_flags))
    err(1, "");

  return 0;
}
