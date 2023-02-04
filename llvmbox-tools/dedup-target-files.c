// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"

typedef struct {
  sha256sum_t hash;    // contents & relpath
  target_t*   target;  //
  char*       relpath; // e.g. "sys/types.h"
} tfile_t;

typedef array_type(tfile_t) tfilearray_t;


const char* prog;
const char* exe_path;
bool        dryrun = false;
char        basedir[PATH_MAX];
char        tmpbuf[PATH_MAX];

targetarray_t g_targets = {0};
target_t*     g_curr_target;
char          g_curr_subdir[PATH_MAX];
usize         g_curr_subdir_len;
tfilearray_t  g_tfiles = {0};
array_t       g_mvdirs = {0}; // dirs which had files removed from them (sorted unique)


usize base16_encode(char* dst, usize dstcap, const void* src, usize size) {
  assert(dst != NULL);
  assert(src != NULL);
  static const char* hexchars = "0123456789abcdef";
  if (dstcap < size*2)
    return size*2;
  for (usize i = 0; i < size; i++) {
    u8 c = *(u8*)src++;
    if (c < 0x10) {
      dst[0] = '0';
      dst[1] = hexchars[c];
    } else {
      dst[0] = hexchars[c >> 4];
      dst[1] = hexchars[c & 0xf];
    }
    dst += 2;
  }
  return size*2;
}


int target_cmp(const target_t* a, const target_t* b) {
  // Layers:
  //   5. ARCH-SYS.VER
  //   4. ARCH-SYS
  //   3. any-SYS.VER
  //   2. any-SYS
  //   1. any-any
  // Example subdir names:
  //   x86_64-macos.10, x86_64-macos.10-libc
  //   x86_64-macos
  //   any-macos.10
  //   any-macos, any-macos-libc
  //   any-any
  //
  bool a_any_arch = strcmp(a->arch, "any") == 0;
  bool b_any_arch = strcmp(b->arch, "any") == 0;
  if (a_any_arch != b_any_arch) {
    // e.g. a "any-*" scores higher than "ARCH-*"
    return a_any_arch ? -1 : 1;
  }

  bool a_any_sys = strcmp(a->sys, "any") == 0;
  bool b_any_sys = strcmp(b->sys, "any") == 0;
  if (a_any_sys != b_any_sys) {
    // e.g. a "x-any" scores higher than "x-SYS"
    return a_any_sys ? -1 : 1;
  }

  assert(a->sysver != NULL);
  assert(b->sysver != NULL);
  int cmp = strcmp(a->sysver, b->sysver);
  if (cmp == 0)
    return 0;
  return atoi(a->sysver) - atoi(b->sysver);
}


int tfiles_cmp(const void* x, const void* y, void* ctx) {
  const tfile_t* a = x;
  const tfile_t* b = y;

  // <hash>  {"x86_64","linux"}  "x86_64-linux"  "sys/types.h"
  int cmp = memcmp(&a->hash, &b->hash, sizeof(a->hash));
  if (cmp != 0)
    return cmp;

  // same content and path; sort by target system
  cmp = strcmp(a->target->sys, b->target->sys);
  if (cmp != 0)
    return cmp;

  // same content and path will be deduplicated; sort by target layer
  return target_cmp(a->target, b->target);
}


// examples:
//   "a-b" "a-c" -> "a-any"
//   "a-b" "c-d" -> "any-any"
//   "a-b" "a-b" -> "a-b"
//   "a-b.1" "a-b.2" -> "a-b"
//   "a-any.1" "a-b.1" -> "a-any"
target_t target_intersection(target_t a, target_t b) {
  target_t c = a;

  if (strcmp(a.arch, b.arch) != 0)
    c.arch = "any";

  if (strcmp(a.sys, b.sys) != 0) {
    c.sys = "any";
    c.sysver = "";
  } else if (strcmp(a.sysver, b.sysver) != 0) {
    c.sysver = "";
  }

  if (strcmp(a.suffix, b.suffix) != 0)
    c.suffix = "";

  return c;
}


bool dryrun_aware_rm(const char* filename) {
  if (dryrun) {
    struct stat st = {0};
    lstat(filename, &st);
    printf("%s %s\n", S_ISDIR(st.st_mode) ? "rmdir" : "rm", filename);
    return true;
  }
  dlog("  rm %s", filename);
  if (remove(filename) == 0)
    return true;
  warn("failed to remove %s", filename);
  return false;
}


bool dryrun_aware_mv(const char* curr_filename, const char* new_filename) {
  if (dryrun) {
    printf("mv %s %s\n", curr_filename, new_filename);
    return true;
  }
  dlog("  mv %s -> %s", curr_filename, new_filename);
  if (rename(curr_filename, new_filename) == 0)
    return true;
  warn("failed to move %s -> %s", curr_filename, new_filename);
  return false;
}


int str_cmp(const void* a, const void* b, void* ctx) {
  return strcmp(*(const char**)a, *(const char**)b);
}

int str_rcmp(const void* a, const void* b, void* ctx) {
  return strcmp(*(const char**)b, *(const char**)a);
}


void array_sorted_add_str(array_t* a, const char* str, array_sorted_cmp_t cmpf) {
  const char** vp = array_sorted_assign(const char*, a, &str, cmpf, NULL);
  if (!vp) {
    warn("array_sorted_assign");
  } else if (*vp == NULL) {
    if ((*vp = strdup(str)) == NULL)
      err(1, "strdup");
  }
}


bool target_sys_versions(
  const char* sys, const char** archv, u32 archc, array_t* sorted_set_result)
{
  for (usize i = 0; i < supported_targets_count; i++) {
    const target_t* t = &supported_targets[i];
    if (strcmp(t->sys, sys) != 0)
      continue;

    bool arch_match = archc == 0;
    if (strcmp(t->arch, "any") == 0) {
      arch_match = true;
    } else for (u32 j = 0; j < archc; j++) {
      if (strcmp(t->arch, archv[j]) == 0) {
        arch_match = true;
        break;
      }
    }
    if (!arch_match)
      continue;

    if (*t->sysver == 0)
      continue;
    array_sorted_add_str(sorted_set_result, t->sysver, str_cmp);
  }
  return true;
}


void mvdirs_add(const char* path) {
  array_sorted_add_str(&g_mvdirs, path, str_rcmp);
}


char* dirname_mut(char* path) {
  char* p = strrchr(path, '/');
  if (p) {
    // keep "/" at the end for nicer "dryrun" messages
    p += (usize)dryrun;
    *p = 0;
  }
  return path;
}


void dedup_tfiles(tfile_t* tfv, u32 tfc) {
  // We begin by selecting the highest-level destdir, where to consolidate files.
  //
  // Note that the list is sorted by higest level first.
  // In some cases tfv[0].targetdir is the right choice, for example:
  //   [0] any-macos         xlocale.h
  //   [1] x86_64-macos      xlocale.h
  //   [2] x86_64-macos.10   xlocale.h
  //   [3] aarch64-macos.11  xlocale.h
  //   [4] x86_64-macos.11   xlocale.h
  //   [5] aarch64-macos.12  xlocale.h
  // But there are cases like this where we have to find a common prefix,
  // or the set intersection of targets:
  //   [0] x86_64-macos.10   xlocale.h
  //   [1] aarch64-macos.11  xlocale.h
  //   [2] x86_64-macos.11   xlocale.h
  //   [3] aarch64-macos.12  xlocale.h
  //
  char srcpath[PATH_MAX]; // e.g. "x86_64-macos.10/sys/errno.h"
  char dstpath[PATH_MAX]; // e.g. "any-macos/sys/errno.h"
  char* array_st[10]; // 10: number large enough according to supported_targets

  // find system (note: all entries might contain sys="any")
  const char* sys = ""; // empty string signifies "any"
  for (u32 i = 0; i < tfc; i++) {
    if (strcmp(tfv[i].target->sys, "any") != 0) {
      sys = tfv[i].target->sys;
      break;
    }
  }

  // Find set of archs that the files span.
  // We will consider system versions only of these archs during the next step.
  array_t archs = {.ptr=(u8*)array_st,.cap=countof(array_st)};
  for (u32 i = 0; i < tfc; i++) {
    if (strcmp(tfv[i].target->arch, "any") != 0)
      array_sorted_add_str(&archs, tfv[i].target->arch, str_cmp);
  }

  // If not all versions are covered, don't merge.
  // This avoids including next-gen headers in older system versions.
  // Note: We never combine files of different systems, so we only need to check
  // versions of the one system.
  array_t versions = {.ptr=(u8*)array_st,.cap=countof(array_st)};
  if (!target_sys_versions(sys, (const char**)archs.ptr, archs.len, &versions))
    err(1, "target_sys_versions");
  u32 nversions_covered = 0;
  for (u32 i = 0; i < versions.len; i++) {
    const char* sysver = array_at(const char*, &versions, i);
    for (u32 i = 0; i < tfc; i++) {
      if (strcmp(tfv[i].target->sysver, sysver) == 0) {
        nversions_covered++;
        break;
      }
    }
  }

  if (nversions_covered < versions.len) {
    // not all versions are covered
    dlog("%s: only %u/%u versions covered",
      tfv[0].relpath, nversions_covered, versions.len);

    // Find out if tfv contains a file in a directory on a lower layer.
    // If that is true, then we can remove all other files.
    for (u32 i = 0; i < tfc; i++) {
      if (*tfv[i].target->sysver != 0 || strcmp(tfv[i].target->sys, "any") == 0) {
        // e.g. "any-macos.10" or "x86_64-any"
        continue;
      }
      // e.g. "x86_64-macos" or "any-macos" (no version)
      dlog("%s is represented at lower-level: " TARGET_FMT,
        tfv[0].relpath, TARGET_FMT_ARGS(*tfv[i].target));
      bool ok = true;
      for (i = 0; i < tfc; i++) {
        if (*tfv[i].target->sysver == 0 || strcmp(tfv[i].target->sys, "any") == 0)
          continue; // keep
        target_str(*tfv[i].target, tmpbuf, sizeof(tmpbuf));
        if (path_join(srcpath, tmpbuf, tfv[0].relpath) < 0)
          err(1, "path_join %s, %s", tmpbuf, tfv[0].relpath);
        ok &= dryrun_aware_rm(srcpath);
        mvdirs_add(dirname_mut(srcpath));
      }
      if (!ok)
        exit(1);
      break;
    }
    return;
  }

  target_t common_target = *tfv[0].target;
  for (u32 i = 1; i < tfc; i++)
    common_target = target_intersection(common_target, *tfv[i].target);

  target_str(common_target, tmpbuf, sizeof(tmpbuf));
  if (path_join(dstpath, tmpbuf, tfv[0].relpath) < 0)
    err(1, "path_join %s, %s", tmpbuf, tfv[0].relpath);

  printf("%s: consolidate %u files\n", dstpath, tfc);

  // create destination directories
  char* p = strrchr(dstpath, '/');
  assert(p != NULL);
  *p = 0;
  if (dryrun) {
    printf("mkdir -p %s\n", dstpath);
  } else {
    dlog("  mkdirs %s", dstpath);
    if (!mkdirs(dstpath, 0755))
      err(1, "mkdirs %s", dstpath);
  }
  *p = '/';

  bool ok = true;

  for (u32 i = 0; i < tfc; i++) {
    target_str(*tfv[i].target, tmpbuf, sizeof(tmpbuf));
    if (path_join(srcpath, tmpbuf, tfv[0].relpath) < 0)
      err(1, "path_join %s, %s", tmpbuf, tfv[0].relpath);
    if (i == 0) {
      ok &= dryrun_aware_mv(srcpath, dstpath);
    } else {
      ok &= dryrun_aware_rm(srcpath);
    }

    // add srcdir, to be considered for removal later (if empty)
    // dirname_mut: remove basename from srcpath
    mvdirs_add(dirname_mut(srcpath));
  }

  if (!ok)
    exit(1);
}


void process_tfiles() {
  lb_qsort(g_tfiles.v, g_tfiles.len, sizeof(tfile_t), tfiles_cmp, NULL);

  u32 i = 0, range_start = 0;

  for (; i < g_tfiles.len; i++) {
    tfile_t* tf = &g_tfiles.v[i];

    // char hash[SHA256_SUM_SIZE*2];
    // base16_encode(hash, sizeof(hash), &tf->hash, sizeof(tf->hash));
    // printf("%.22s  " TARGET_FMT "\t%s\n",
    //   hash, TARGET_FMT_ARGS(*tf->target), tf->relpath);

    if (i == 0)
      continue;

    tfile_t* tf_prev = &g_tfiles.v[i - 1];

    if (memcmp(&tf->hash, &tf_prev->hash, sizeof(tf->hash)) != 0 ||
        strcmp(tf->target->sys, tf_prev->target->sys) != 0)
    {
      // i is start of new range, i-1 was last of prev range
      if (i - range_start > 1)
        dedup_tfiles(&g_tfiles.v[range_start], i - range_start);
      range_start = i;
    }
  }
  // handle tail
  if (i - range_start > 1)
    dedup_tfiles(&g_tfiles.v[range_start], i - range_start);
}


int file_visitor(const char* path, const struct stat* sb, int type, struct FTW* ftwp) {
  if (type != FTW_F)
    return 0;
  if (str_has_suffix(path, ".DS_Store"))
    return 0;

  // printf("%s\n", path);

  tfile_t* tf = array_alloc(tfile_t, &g_tfiles, 1);
  if (!tf)
    return 1;
  tf->target = g_curr_target;
  tf->relpath = strdup(path + (g_curr_subdir_len + 1));

  slice_t contents;
  if (!load_file(path, &contents)) {
    warn("read %s", path);
    return 1;
  }

  sha256_t s;
  sha256_init(&s, (u8*)&tf->hash);
  sha256_write(&s, contents.p, contents.len);
  sha256_write(&s, tf->relpath, strlen(tf->relpath));
  sha256_close(&s);

  unload_file(&contents);

  // char tmp[SHA256_SUM_SIZE*2];
  // base16_encode(tmp, sizeof(tmp), &tf->hash, sizeof(tf->hash));
  // printf("%.*s %s\n", (int)sizeof(tmp), tmp, path);

  return 0;
}


bool visit_subdir(target_t* target) {
  #if DEBUG
    target_str(*target, tmpbuf, sizeof(tmpbuf));
    dlog("%s", tmpbuf);
  #endif

  g_curr_target = target;
  g_curr_subdir_len = (usize)target_str(*target, g_curr_subdir, sizeof(g_curr_subdir));

  int fd_limit = 256;
  if (nftw(g_curr_subdir, file_visitor, fd_limit, FTW_DEPTH | FTW_PHYS) != 0)
    return false;

  return true;
}


bool dir_isempty(const char* path, bool* has_DS_Store) {
  DIR* dirp = opendir(path);
  if (!dirp)
    err(1, "%s", path);
  *has_DS_Store = false;
  struct dirent ent;
  struct dirent* result;
  bool is_empty = true;
  while (readdir_r(dirp, &ent, &result) == 0 && result) {
    if (*ent.d_name == 0)
      continue;
    if (*ent.d_name == '.') {
      if (ent.d_name[1] == 0 || (ent.d_name[1] == '.' && ent.d_name[2] == 0))
        continue;
      if (strcmp(ent.d_name, ".DS_Store") == 0) {
        *has_DS_Store = true;
        continue;
      }
    }
    is_empty = false;
    break;
  }
  closedir(dirp);
  return is_empty;
}


void remove_empty_dirs() {
  dlog("remove_empty_dirs");
  // lb_qsort(g_mvdirs.ptr, g_mvdirs.len, sizeof(void*), strptr_cmp_r, NULL);
  for (u32 i = 0; i < g_mvdirs.len; i++) {
    const char* path = array_at(const char*, &g_mvdirs, i);
    bool has_DS_Store = false;
    if (!dryrun && !dir_isempty(path, &has_DS_Store))
      continue;
    if (has_DS_Store) {
      if (path_join(tmpbuf, path, ".DS_Store") < 0)
        err(1, "path_join");
      dryrun_aware_rm(tmpbuf);
    }
    dryrun_aware_rm(path);
  }
}


bool target_is_supported(target_t t) {
  bool arch_ok = strcmp(t.arch, "any") == 0;
  bool sys_ok = strcmp(t.sys, "any") == 0;

  for (usize i = 0; i < supported_targets_count; i++) {
    const target_t* t2 = &supported_targets[i];

    if (!arch_ok && strcmp(t.arch, t2->arch) == 0)
      arch_ok = true;

    if (!sys_ok && strcmp(t.sys, t2->sys) == 0)
      sys_ok = *t2->sysver == 0 || *t.sysver == 0 || strcmp(t.sysver, t2->sysver) == 0;

    if (arch_ok && sys_ok)
      return true;
  }
  return false;
}


void cl_usage() {
  printf(
    "Consolidate duplicate files in directories of \"target\" pattern\n"
    "usage: %s [options] <basedir>\n"
    "Options:\n"
    "  -p  Just print what would be done (dry run; no modifications)\n"
    "  -h  Show help and exit\n"
    "<basedir>\n"
    "  Directory to scan for subdirectories of target pattern.\n"
    , prog);
}


int main(int argc, char* argv[]) {
  prog = argv[0];
  opterr = 0; // don't print built-in error messages
  for (int c; (c = getopt(argc, argv, "oL:ph")) != -1; ) switch (c) {
    case 'p': dryrun = true; break;
    case 'h': cl_usage(); exit(0); break;
    case '?':
      warnx("unrecognized option -%c", optopt);
      return 1;
  }
  if (optind == argc)
    errx(1, "missing <basedir> argument");
  if (argc - optind > 1)
    errx(1, "extraneous <basedir> argument (just one is accepted)");

  // resolve path to executable
  if ((exe_path = get_exe_path(argv[0])) == NULL)
    err(1, "unable to infer path to executable %s", argv[0]);

  // resolve path to basedir
  if (!path_resolve(basedir, argv[optind]) || !isdir(basedir))
    err(1, "%s", argv[optind]);

  // change dir to basedir for shorter paths
  if (chdir(basedir) != 0)
    err(1, "chdir %s", basedir);

  // find all subdirs
  dlog("basedir: %s", basedir);
  DIR* dirp = opendir(".");
  if (!dirp)
    err(1, "%s", basedir);
  struct dirent ent;
  struct dirent* result;
  // char subdir_path[PATH_MAX];
  while (readdir_r(dirp, &ent, &result) == 0 && result) {
    if (*ent.d_name == 0)
      continue;
    if (*ent.d_name == '.') {
      // ignore "." and ".." entries
      if (ent.d_name[1] == 0 || (ent.d_name[1] == '.' && ent.d_name[2] == 0))
        continue;
      // ignore annoying macOS ".DS_Store" files
      if (strcmp(ent.d_name, ".DS_Store") == 0)
        continue;
    }
    if (ent.d_type != DT_DIR)
      continue;

    target_t* target = array_alloc(target_t, &g_targets, 1);
    if (!target)
      err(1, "");
    if (!target_parse(target, ent.d_name, TARGET_PARSE_QUIET)
        // || !target_is_supported(*target)
    ){
      #if DEBUG
        bool parse_ok = target_parse(target, ent.d_name, TARGET_PARSE_QUIET);
        dlog("skip %s (%s)", ent.d_name, parse_ok ? "not-supported" : "parse-fail");
      #endif
      g_targets.len--;
      continue;
    }

    // we rely on the target to get to the dir name
    snprintf(tmpbuf, sizeof(tmpbuf), TARGET_FMT, TARGET_FMT_ARGS(*target));
    if (strcmp(ent.d_name, tmpbuf) != 0) {
      fprintf(stderr, "warning: dir %s is not of canonical form (%s) -- ignoring\n",
        ent.d_name, tmpbuf);
      g_targets.len--;
    }
  }
  closedir(dirp);

  // visit subdirs
  for (u32 i = 0; i < g_targets.len; i++) {
    // if (strcmp("macos", g_targets.v[i].sys)) continue; // XXX debug
    // if (strcmp("x86_64", g_targets.v[i].arch)) continue; // XXX debug
    if (!visit_subdir(&g_targets.v[i]))
      err(1, "%s", ent.d_name);
  }

  // consolidate files
  process_tfiles();

  // remove now-empty directories
  remove_empty_dirs();

  return 0;
}
