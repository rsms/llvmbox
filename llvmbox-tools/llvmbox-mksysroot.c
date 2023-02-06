// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"

// paths relative to self executable
#define SYSROOTS_DIR  "../../sysroots"
#define LLVMBIN_DIR   ".."

// paths relative to sysroots_dir
#define MUSL_SRCDIR "libc/musl"

// prefix of default output directory (overridden by -o)
#define OUTDIR_PREFIX "sysroot-"

static bool opt_l = false;        // -l
static bool opt_f = false;        // -f
static char* user_outdir = "";    // -o
static const char* prog;          // argv[0]
static const char* exe_path;      //
static char* sysroots_dir = NULL; //
static char* llvmbin_dir  = NULL; // -L


bool target_sysroot_dir(target_t target, const char* infix, char result[PATH_MAX]) {
  int n;
  char tmp[PATH_MAX];
  char infix_sep[2] = {infix && *infix ? '/' : 0, 0};
  n = snprintf(tmp, sizeof(tmp), "%s/%s%s" TARGET_FMT "%s",
    sysroots_dir, infix, infix_sep, TARGET_FMT_ARGS(target),
    target.suffix ? target.suffix : "");
  if (n >= PATH_MAX)
    return false;
  // dlog("consider srcdir: %s", relpath(NULL, tmp));
  if (!path_resolve(result, tmp) || !isdir(result))
    return false;
  return true;
}


int target_cmp(const void* p1, const void* p2, void* ctx) {
  const target_t* a = p1;
  const target_t* b = p2;
  char* tmp = ctx;
  target_str(*a, tmp, PATH_MAX);
  target_str(*b, tmp+PATH_MAX, PATH_MAX);
  return strcmp(tmp, tmp+PATH_MAX);
}


void print_target_list() {
  char tmp[PATH_MAX*2];
  target_t targets[SUPPORTED_TARGETS_COUNT];
  memcpy(targets, supported_targets, sizeof(targets));
  lb_qsort(targets, SUPPORTED_TARGETS_COUNT, sizeof(target_t), target_cmp, tmp);
  for (usize i = 0; i < SUPPORTED_TARGETS_COUNT; i++)
    printf(TARGET_FMT "\n", TARGET_FMT_ARGS(targets[i]));
}


char* create_outdir(bumpalloc_t* ma, char tmp[PATH_MAX], target_t target) {
  if (*user_outdir)
    return user_outdir;
  int n = snprintf(tmp, PATH_MAX, "%s" TARGET_FMT,
    OUTDIR_PREFIX, TARGET_FMT_ARGS(target));
  if (n >= PATH_MAX) {
    warnx("outdir too long");
    return NULL;
  }
  if (access(tmp, F_OK) == 0) {
    if (!opt_f) {
      errno = EEXIST;
      return NULL;
    }
    printf("Replacing existing directory: %s\n", relpath(NULL, tmp));
    if (!rmfile_recursive(tmp) && errno != EEXIST)
      return NULL;
  }
  if (!mkdirs(tmp, 0755)) {
    warn("Failed to create directory: %s", tmp);
    return NULL;
  }
  return bumpalloc_strdup(ma, tmp);
}


bool copy_merge_one(const char* dstdir, const char* srcdir) {
  printf("* %s -> %s\n", relpath(NULL, srcdir), relpath(NULL, dstdir));
  int flags = 0;
  bool ok = copy_merge(srcdir, dstdir, flags);
  if (!ok)
    warn("failed to copy dir tree %s -> %s", srcdir, dstdir);
  return ok;
}

bool copy_merge_all(const char* dstdir, const char** srcdirv, usize srcdirc) {
  int ok = true;
  for (u32 i = 0; i < srcdirc; i++)
    ok *= (int)copy_merge_one(dstdir, srcdirv[i]);
  return (bool)ok;
}


bool gen_sysroot_copy_dirs(char tmp[PATH_MAX], target_t target, const char* outdir) {
  usize search_targets_len = 0;
  target_t search_targets[9] = {0};
  #define SEARCH_TARGET(ARCH, SYS, SYSVER, SUFFIX) \
    search_targets[search_targets_len++] = (target_t){ \
      .arch=(ARCH), .sys=(SYS), .sysver=(SYSVER), .suffix=(SUFFIX) }

  // any-any
  // any-{SYS}
  // any-{SYS}-libc
  // any-{SYS}.{VER}
  // any-{SYS}.{VER}-libc
  // {ARCH}-{SYS}
  // {ARCH}-{SYS}-libc
  // {ARCH}-{SYS}.{VER}
  // {ARCH}-{SYS}.{VER}-libc
  SEARCH_TARGET("any", "any", "", NULL);
  SEARCH_TARGET("any", target.sys, "", NULL);
  SEARCH_TARGET("any", target.sys, "", "-libc");
  if (target.sysver && *target.sysver) {
    SEARCH_TARGET("any", target.sys, target.sysver, NULL);
    SEARCH_TARGET("any", target.sys, target.sysver, "-libc");
  }
  SEARCH_TARGET(target.arch, target.sys, "", NULL);
  SEARCH_TARGET(target.arch, target.sys, "", "-libc");
  if (target.sysver && *target.sysver) {
    SEARCH_TARGET(target.arch, target.sys, target.sysver, NULL);
    SEARCH_TARGET(target.arch, target.sys, target.sysver, "-libc");
  }

  const char* src_incdirv[countof(search_targets)] = {0}; u32 src_incdirc = 0;
  const char* src_libdirv[countof(search_targets)] = {0}; u32 src_libdirc = 0;

  for (usize i = 0; i < countof(search_targets); i++) {
    target_t t = search_targets[i];
    if (!t.arch)
      continue;
    if (target_sysroot_dir(t, "include", tmp))
      src_incdirv[src_incdirc++] = strdup(tmp);
    if (target_sysroot_dir(t, "lib", tmp))
      src_libdirv[src_libdirc++] = strdup(tmp);
  }

  // copy include dirs
  if (snprintf(tmp, PATH_MAX, "%s/include", outdir) >= PATH_MAX) {
    warnx("outdir too long: %s", outdir);
    return NULL;
  }
  if (!copy_merge_all(tmp, src_incdirv, src_incdirc))
    return false;

  // copy lib dirs
  snprintf(tmp, PATH_MAX, "%s/lib", outdir);
  if (!copy_merge_all(tmp, src_libdirv, src_libdirc))
    return false;

  return true;
}


bool build_libc_musl(
  bumpalloc_t* ma, target_t target, const char* outdir, char tmppath[PATH_MAX])
{
  char* clang = path_join_dup(ma, llvmbin_dir, "clang");

  char* musl_srcdir = path_join_dup(ma, sysroots_dir, MUSL_SRCDIR);
  if (!musl_srcdir || !isdir(musl_srcdir))
    err(1, "musl_srcdir: %s", musl_srcdir);

  char* musl_idir_any = path_join_dup(ma, musl_srcdir, "include");
  if (!musl_idir_any || !isdir(musl_idir_any))
    err(1, "musl_idir_any: %s", musl_idir_any);

  dlog("musl_srcdir: %s", musl_srcdir);

  // // copy arch-dependent headers
  // if (path_join(tmppath, outdir, "include") < 0)
  //   return false;
  // if (!copy_merge_one(tmppath, musl_idir_any))
  //   return false;

  // include/alltypes.h.in needs to be processed

  // from musl/Makefile:
  //   obj/include/bits/alltypes.h: \
  //       arch/$(ARCH)/bits/alltypes.h.in \
  //       include/alltypes.h.in \
  //       tools/mkalltypes.sed
  //     sed -f tools/mkalltypes.sed
  //            arch/$(ARCH)/bits/alltypes.h.in
  //            include/alltypes.h.in
  //          > obj/include/bits/alltypes.h


  warnx("%s is work in progress", __FUNCTION__);
  errno = ECANCELED;
  return false;
}


bool gen_sysroot(bumpalloc_t* ma, const char* target_str) {
  char tmp[PATH_MAX];

  target_t target;
  if (!target_parse(&target, target_str, TARGET_PARSE_VALIDATE)) {
    warnx("See %s -l for a list of supported targets\n", prog);
    return false;
  }
  if (target.suffix) {
    warnx("invalid target \"%s\", unexpected trailing -%s", target_str, target.suffix);
    return false;
  }
  dlog("target: " TARGET_FMT, TARGET_FMT_ARGS(target));

  char* outdir = create_outdir(ma, tmp, target);
  if (!outdir)
    return false;

  if (!gen_sysroot_copy_dirs(tmp, target, outdir))
    return false;

  if (strcmp(target.sys, "linux") == 0) {
    if (!build_libc_musl(ma, target, outdir, tmp))
      return false;
  } else {
    warnx("libc for %s not implemented", target.sys);
    return false;
  }

  return true;
}


void cl_usage() {
  printf(
    "Build sysroot for target\n"
    "usage: %s [options] <target> ...\n"
    "Options:\n"
    "  -h        Show help and exit\n"
    "  -l        Print list of supported targets\n"
    "  -f        Force creation of <dir>, replacing it if exists\n"
    "  -o <dir>  Write output at <dir> instead of ./sysroot-<target>\n"
    "  -L <dir>  Path to clang & clang++ \"bin\" directory\n"
    "<target>\n"
    "  In the format \"arch-system\" with an optional system version\n"
    "  as a suffix, e.g. \"x86_64-macos.10\". If version is not provided,\n"
    "  the oldest supported version is selected.\n"
    , prog);
}


int main(int argc, char* argv[]) {
  prog = argv[0];

  // memory allocator for stuff that lives until the program ends
  static void* rootmem[4096*2];
  bumpalloc_t rootma = { .start=rootmem, .end=rootmem+sizeof(rootmem), .next=rootmem };

  // parse command line options
  // global state in libc... coolcoolcool:
  //   extern char* optarg;
  //   extern int optind, optopt, opterr;
  opterr = 0; // don't print built-in error messages
  int nerrs = 0;
  for (int c; (c = getopt(argc, argv, "oL:hlf")) != -1; ) switch (c) {
    case 'o': user_outdir = optarg; break;
    case 'L': llvmbin_dir = optarg; break;
    case 'h': cl_usage(); exit(0); break;
    case 'l': opt_l = true; break;
    case 'f': opt_f = true; break;
    case '?':
      if (optopt == 'o' || optopt == 'L') {
        warnx("option -%c requires a value", optopt);
      } else {
        warnx("unrecognized option -%c", optopt);
      }
      nerrs++;
      break;
  }
  if (nerrs)
    return 1;
  int argi = optind;

  // print target list if -l is set
  if (opt_l)
    return print_target_list(), 0;

  // resolve path to executable
  if ((exe_path = get_exe_path(argv[0])) == NULL)
    errx(1, "unable to infer path to executable %s", argv[0]);

  // resolve path to sysroot sources
  sysroots_dir = path_join_dup(&rootma, exe_path, SYSROOTS_DIR);
  if (!sysroots_dir || !isdir(sysroots_dir))
    err(1, "sysroots_dir: %s/%s", exe_path, SYSROOTS_DIR);

  // resolve path to clang, clang++ and lld
  if (llvmbin_dir) {
    // set by user with -L
    const char* uservalue = llvmbin_dir;
    llvmbin_dir = bumpalloc(&rootma, PATH_MAX);
    if (!llvmbin_dir || !path_resolve(llvmbin_dir, uservalue) || !isdir(llvmbin_dir))
      err(1, "%s", uservalue);
  } else {
    llvmbin_dir = path_join_dup(&rootma, exe_path, LLVMBIN_DIR);
    if (!llvmbin_dir || !isdir(sysroots_dir))
      err(1, "llvmbin_dir: %s/%s", exe_path, LLVMBIN_DIR);
  }

  dlog("exe_path:     %s", exe_path);
  dlog("sysroots_dir: %s", sysroots_dir);
  dlog("llvmbin_dir:  %s", llvmbin_dir);

  // process each <target>
  if (argi == argc)
    errx(1, "missing <target> argument");

  if (*user_outdir && argc - argi > 1)
    errx(1, "cannot use option -o <dir> with multiple inputs");

  usize memsize = 32*1024*1024;
  bumpalloc_t ma = { .start = malloc(memsize) };
  ma.next = ma.start;
  ma.end = ma.start + memsize;

  for (; argi < argc; argi++) {
    ma.next = ma.start; // reset
    nerrs += !gen_sysroot(&ma, argv[argi]);
  }

  return !!nerrs;
}
