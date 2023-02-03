// SPDX-License-Identifier: Apache-2.0
#include "llvmbox-tools.h"
#include <libgen.h> // dirname_r

typedef struct {
  union {
    const char* cstr;
    const u8*   bytes;
    const void* p;
  };
  usize len;
} slice_t;

typedef struct {
  const char* arch;
  const char* sys;
  const char* sysver;
  const char* triple; // for clang
} target_t;


#define SYSROOTS_DIR  "../sysroots"  // relative to dir of mksysroot executable
#define OUTDIR_PREFIX "sysroot-"

static bool opt_l = false;      // -l
static char* user_outdir = "";  // -o
static const char* prog;        // argv[0]
static char exe_path[PATH_MAX]; // absolute path to self executable
static char sysroots_dir[PATH_MAX]; // = dirname(exe_path)/SYSROOTS_DIR

static const target_t supported_targets[] = {
  // these must be sorted by sysver (per system)
  {"aarch64", "linux", "",   "aarch64-linux-musl"},
  {"x86_64",  "linux", "",   "x86_64-linux-musl"},
  {"aarch64", "macos", "11", "arm64-apple-darwin20"},
  {"aarch64", "macos", "12", "arm64-apple-darwin21"},
  {"aarch64", "macos", "13", "arm64-apple-darwin22"},
  {"x86_64",  "macos", "10", "x86_64-apple-darwin19"},
  {"x86_64",  "macos", "11", "x86_64-apple-darwin20"},
  {"x86_64",  "macos", "12", "x86_64-apple-darwin21"},
  {"x86_64",  "macos", "13", "x86_64-apple-darwin22"},
};

#define TARGET_FMT "%s-%s%s%s"
#define TARGET_FMT_ARGS(target) \
  (target).arch, \
  (target).sys, \
  (*(target).sysver ? "." : ""), \
  (*(target).sysver ? (target).sysver : "")


bool slice_eq_cstr(slice_t s, const char* cstr) {
  usize len = strlen(cstr);
  return s.len == len && memcmp(s.p, cstr, len) == 0;
}


bool resolve_sysroot_dir(char result[PATH_MAX], const char* infix, target_t target) {
  int n;
  char tmp[PATH_MAX];
  char infix_sep[2] = {infix && *infix ? '/' : 0, 0};
  n = snprintf(tmp, sizeof(tmp), "%s/%s%s" TARGET_FMT,
    sysroots_dir, infix, infix_sep, TARGET_FMT_ARGS(target));
  if (n >= PATH_MAX)
    return false;
  struct stat st;
  if (!resolve_path(result, &st, tmp))
    return false;
  if (!S_ISDIR(st.st_mode)) {
    errno = ENOTDIR;
    return false;
  }
  return true;
}


bool target_parse(target_t* target, const char* target_str) {
  // arch-sys[.ver]
  memset(target, 0, sizeof(*target));
  const char* sysp = strchr(target_str, '-');
  if (!sysp) {
    warnx("invalid target \"%s\", missing system after architecture", target_str);
    return false;
  }
  sysp++;
  const char* endp = target_str + strlen(target_str);
  const char* verp = strchr(sysp, '.');
  slice_t arch = {.p=target_str, .len=(usize)(sysp - 1 - target_str)};
  slice_t sys = {.p=sysp, .len=(usize)((verp ? verp : endp) - sysp)};
  slice_t sysver = {0};
  if (verp) {
    sysver.p = ++verp;
    sysver.len = (usize)(endp - verp);
  };
  // dlog("target_parse(\"%s\") => (%.*s,%.*s,%.*s)", target_str,
  //   (int)arch.len, arch.cstr, (int)sys.len, sys.cstr, (int)sysver.len, sysver.cstr);

  bool found_without_version = false;
  for (usize i = 0; i < countof(supported_targets); i++) {
    const target_t* t = &supported_targets[i];
    if (slice_eq_cstr(arch, t->arch) && slice_eq_cstr(sys, t->sys)) {
      found_without_version = true;
      if (sysver.len == 0 || slice_eq_cstr(sysver, t->sysver)) {
        *target = *t;
        return true;
      }
    }
  }

  if (found_without_version) {
    warnx("unsupported target system version \"%.*s\" of target \"%.*s-%.*s\"",
      (int)sysver.len, sysver.cstr, (int)arch.len, arch.cstr, (int)sys.len, sys.cstr);
  } else {
    warnx("unknown target \"%s\"", target_str);
  }
  return false;
}


void print_target_list() {
  for (usize i = 0; i < countof(supported_targets); i++)
    printf(TARGET_FMT "\n", TARGET_FMT_ARGS(supported_targets[i]));
}


bool set_exe_path(const char* argv0) {
  char tmp[PATH_MAX];

  // absolute path
  if (*argv0 == '/') {
    if (strlen(argv0) >= sizeof(exe_path)) {
      dlog("strlen(argv0)");
      return false;
    }
    memcpy(exe_path, argv0, strlen(argv0) + 1);
    return true;
  }

  // relative path
  if (strchr(argv0, '/')) {
    if (!getcwd(tmp, PATH_MAX)) {
      dlog("getcwd");
      return false;
    }
    return resolve_path2(exe_path, tmp, argv0);
  }

  // look in PATH
  const char* PATH = getenv("PATH");
  if (!PATH || strlen(PATH) >= PATH_MAX) {
    dlog("getenv(PATH)");
    return false;
  }
  memcpy(tmp, PATH, strlen(PATH));
  for (char* state = tmp, *dir; (dir = strsep(&state, ":")) != NULL; ) {
    // dlog("- %s", dir);
    if (resolve_path2(exe_path, dir, argv0))
      return true;
  }

  return false;
}


const char* create_outdir(char tmp[PATH_MAX], target_t target) {
  if (*user_outdir)
    return user_outdir;
  int n = snprintf(tmp, PATH_MAX, "%s" TARGET_FMT,
    OUTDIR_PREFIX, TARGET_FMT_ARGS(target));
  if (n >= PATH_MAX) {
    warnx("outdir too long");
    return NULL;
  }
  if (!mkdirs(tmp, 0755)) {
    warn("failed to create directory: %s", tmp);
    return NULL;
  }
  return strdup(tmp);
}


const char* cached_cwd() {
  static char cwd[PATH_MAX] = {0};
  if (cwd[0] == 0 && !getcwd(cwd, PATH_MAX)) {
    cwd[0] = '/';
    cwd[1] = 0;
  }
  return cwd;
}


const char* relpath(const char* parent, const char* path) {
  if (!parent)
    parent = cached_cwd();
  usize parentlen = strlen(parent);
  if (parentlen < 2 || path[0] != '/' || strncmp(parent, path, parentlen) != 0)
    return path;
  return path + parentlen + 1;
}


bool copy_merge_all(const char* dstdir, const char** srcdirv, usize srcdirc) {
  for (u32 i = 0; i < srcdirc; i++) {
    printf("* %s -> %s\n", relpath(NULL, srcdirv[i]), relpath(NULL, dstdir));
    copy_merge_t cm = { .overwrite = true };
    if (!copy_merge(&cm, dstdir, srcdirv[i])) {
      warn("failed to copy dir tree %s -> %s", srcdirv[i], dstdir);
      return false;
    }
  }
  return true;
}


bool gen_sysroot(const char* target_str) {
  char tmp[PATH_MAX];

  target_t target;
  if (!target_parse(&target, target_str)) {
    warnx("See %s -l for a list of supported targets\n", prog);
    return false;
  }
  dlog("target: " TARGET_FMT, TARGET_FMT_ARGS(target));

  const char* outdir = create_outdir(tmp, target);
  if (!outdir)
    return false;

  // find sysroot source directories
  target_t search_targets[5] = {
    // any-any
    // any-{SYS}
    // any-{SYS}.{VER}
    // {ARCH}-{SYS}
    // {ARCH}-{SYS}.{VER}
    {.arch="any", .sys="any", .sysver=""},
    {.arch="any", .sys=target.sys, .sysver=""},
    {.arch=(*target.sysver ? "any" : ""), .sys=target.sys, .sysver=target.sysver},
    {.arch=(*target.sysver ? target.arch : ""), .sys=target.sys, .sysver=""},
    target,
  };
  const char* src_incdirv[countof(search_targets)] = {0}; u32 src_incdirc = 0;
  const char* src_libdirv[countof(search_targets)] = {0}; u32 src_libdirc = 0;

  for (usize i = 0; i < countof(search_targets); i++) {
    target_t t = search_targets[i];
    if (*t.arch == 0)
      continue;
    if (resolve_sysroot_dir(tmp, "include", t))
      src_incdirv[src_incdirc++] = strdup(tmp);
    if (resolve_sysroot_dir(tmp, "lib", t))
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


void cl_usage() {
  printf(
    "Build sysroot for target\n"
    "usage: %s [options] <target> ...\n"
    "Options:\n"
    "  -h        Show help and exit\n"
    "  -l        Print list of supported targets\n"
    "  -o <dir>  Write output at <dir> instead of ./sysroot-<target>\n"
    "<target>\n"
    "  In the format \"arch-system\" with an optional system version\n"
    "  as a suffix, e.g. \"x86_64-macos.10\". If version is not provided,\n"
    "  the oldest supported version is selected.\n"
    , prog);
}


int main(int argc, char* argv[]) {
  prog = argv[0];

  // parse command line options
  // global state in libc... coolcoolcool:
  //   extern char* optarg;
  //   extern int optind, optopt, opterr;
  opterr = 0; // don't print built-in error messages
  int nerrs = 0;
  for (int c; (c = getopt(argc, argv, "o:hl")) != -1; ) switch (c) {
    case 'h': cl_usage(); exit(0); break;
    case 'l': opt_l = true; break;
    case 'o': user_outdir = optarg; break;
    case '?':
      if (optopt == 'o') {
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
  if (!set_exe_path(argv[0]))
    errx(1, "unable to infer path to executable %s", argv[0]);

  // resolve path to sysroots directory
  if (!dirname_r(exe_path, sysroots_dir))
    err(1, "dirname(exe_path)");
  if (!resolve_path2(sysroots_dir, sysroots_dir, SYSROOTS_DIR))
    errx(1, "can not find \"sysroots\" directory at %s", sysroots_dir);
  dlog("sysroots_dir: %s", sysroots_dir);

  // process each <target>
  if (argi == argc) {
    errx(1, "missing <target> argument");
  } else {
    if (*user_outdir && argc - argi > 1)
      errx(1, "cannot use option -o <dir> with multiple inputs");
    for (; argi < argc; argi++)
      nerrs += !gen_sysroot(argv[argi]);
  }

  return !!nerrs;
}
