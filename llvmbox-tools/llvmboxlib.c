// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"
#include <sys/mman.h>
#ifdef __APPLE__
  #include <sys/clonefile.h>
#endif


#ifdef WIN32
  #define PATH_SEP       '\\'
  #define PATH_SEP_STR   "\\"
  #define PATH_DELIM     ';'
  #define PATH_DELIM_STR ";"
#else
  #define PATH_SEP       '/'
  #define PATH_SEP_STR   "/"
  #define PATH_DELIM     ':'
  #define PATH_DELIM_STR ":"
#endif

#define FOR_EACH_SUPPORTED_TARGET(_) \
  /* these must be sorted by sysver (per system) */\
  /* _(arch, sys, sysver, triple) */\
  _("aarch64", "linux", "",   "aarch64-linux-musl") \
  _("x86_64",  "linux", "",   "x86_64-linux-musl") \
  _("aarch64", "macos", "11", "arm64-apple-darwin20") \
  _("aarch64", "macos", "12", "arm64-apple-darwin21") \
  _("aarch64", "macos", "13", "arm64-apple-darwin22") \
  _("x86_64",  "macos", "10", "x86_64-apple-darwin19") \
  _("x86_64",  "macos", "11", "x86_64-apple-darwin20") \
  _("x86_64",  "macos", "12", "x86_64-apple-darwin21") \
  _("x86_64",  "macos", "13", "x86_64-apple-darwin22") \
// end FOR_EACH_SUPPORTED_TARGET

const target_t supported_targets[] = {
  #define _(arch, sys, sysver, triple) {(arch), (sys), (sysver), ""},
  FOR_EACH_SUPPORTED_TARGET(_)
  #undef _
};
const char* const supported_target_triples[] = {
  #define _(arch, sys, sysver, triple) triple,
  FOR_EACH_SUPPORTED_TARGET(_)
  #undef _
};
const usize supported_targets_count = countof(supported_targets);


static char _exe_path[PATH_MAX];
static char _exe_path_init = false;


int path_clean(char result[PATH_MAX], const char* restrict path) {
  return path_cleann(result, path, strlen(path));
}


int path_cleann(char result[PATH_MAX], const char* restrict path, usize len) {
  usize r = 0;      // read offset
  usize w = 0;      // write offset
  int wl = 0;       // logical bytes written
  usize dotdot = 0; // w offset of most recent ".."

  #define DST_APPEND(c) ( result[w] = c, w += (usize)(w < (PATH_MAX-1)), wl++ )
  #define IS_SEP(c)     ((c) == PATH_SEP)

  if (len == 0) {
    DST_APPEND('.');
    goto end;
  }

  bool rooted = IS_SEP(path[0]);
  if (rooted) {
    DST_APPEND(PATH_SEP);
    r = 1;
    dotdot++;
  }

  while (r < len) {
    if (IS_SEP(path[r]) || (path[r] == '.' && (r+1 == len || IS_SEP(path[r+1])))) {
      // "/" or "."
      r++;
    } else if (path[r] == '.' && path[r+1] == '.' && (r+2 == len || IS_SEP(path[r+2]))) {
      // ".."
      r += 2;
      if (w > dotdot) {
        // can backtrack
        w--;
        while (w > dotdot && !IS_SEP(result[w]))
          w--;
      } else if (!rooted) {
        // cannot backtrack, but not rooted, so append ".."
        if (w > 0)
          DST_APPEND(PATH_SEP);
        DST_APPEND('.');
        DST_APPEND('.');
        dotdot = w;
      }
    } else {
      // actual path component; add slash if needed
      if ((rooted && w != 1) || (!rooted && w != 0))
        DST_APPEND(PATH_SEP);
      // copy
      for (; r < len && !IS_SEP(path[r]); r++)
        DST_APPEND(path[r]);
    }
  }

  if (w == 0) // "" => "."
    DST_APPEND('.');

  #undef DST_APPEND
  #undef IS_SEP

end:
  result[w] = 0;
  return wl;
}


int path_join(char result[PATH_MAX], const char* path1, const char* path2) {
  char tmp[PATH_MAX];
  int n = snprintf(tmp, PATH_MAX, "%s" PATH_SEP_STR "%s", path1, path2);
  if (n >= PATH_MAX)
    errno = EOVERFLOW;
  n = path_cleann(result, tmp, (usize)n);
  return n >= PATH_MAX ? -1 : n;
}


char* path_join_dup(bumpalloc_t* ma, const char* path1, const char* path2) {
  char* s = bumpalloc(ma, PATH_MAX);
  if (!s)
    return NULL;
  int n = path_join(s, path1, path2);
  if (n < 0) {
    bumpalloc_resize(ma, s, PATH_MAX, 0);
    return NULL;
  }
  bumpalloc_resize(ma, s, PATH_MAX, n + 1);
  return s;
}


bool path_resolve(char result[PATH_MAX], const char* path) {
  assert(strlen(path) < PATH_MAX);
  return realpath(path, result) != NULL;
}


bool path_join_resolve(char result[PATH_MAX], const char* path1, const char* path2) {
  char tmp[PATH_MAX];
  if (path_join(tmp, path1, path2) < 0)
    return false;
  return path_resolve(result, tmp);
}


usize path_common_prefix_len(const char* a, const char* b) {
  const char* start = a;
  const char* end = a;
  while (*a && *a++ == *b++)
    if (*a == '/') end = a+1;
  return (usize)(end - start);
}


bool isdir(const char* path) {
  struct stat st;
  if (stat(path, &st) != 0)
    return false;
  if (!S_ISDIR(st.st_mode)) {
    errno = ENOTDIR;
    return false;
  }
  return true;
}


static const char* cached_cwd() {
  static char cwd[PATH_MAX] = {0};
  if (cwd[0] == 0 && !getcwd(cwd, PATH_MAX)) {
    cwd[0] = PATH_SEP;
    cwd[1] = 0;
  }
  return cwd;
}


const char* relpath(const char* parent, const char* path) {
  if (!parent)
    parent = cached_cwd();
  usize parentlen = strlen(parent);
  if (parentlen < 2 || path[0] != PATH_SEP || strncmp(parent, path, parentlen) != 0)
    return path;
  return path + parentlen + 1;
}


static bool _mkdir(const char* path, mode_t mode) {
  struct stat st;
  if (mkdir(path, mode) == 0)
    return true;
  if (errno != EEXIST || stat(path, &st) != 0)
    return false;
  if (!S_ISDIR(st.st_mode)) {
    errno = ENOTDIR;
    return false;
  }
  return true;
}


bool mkdirs(const char *path, mode_t mode) {
  char tmp[PATH_MAX];
  usize len = strlen(path);
  if (len >= PATH_MAX) {
    errno = EOVERFLOW;
    return false;
  }
  memcpy(tmp, path, len + 1);
  errno = 0;
  for (char* p = tmp + 1; *p; p++) {
    if (*p != '/')
      continue;
    *p = 0;
    if (!_mkdir(tmp, mode))
      return false;
    *p = '/';
  }
  return _mkdir(tmp, mode);
}


static int rmfile_recursive_cb(
  const char* path, const struct stat* sb, int typeflag, struct FTW* ftwp)
{
  int r = remove(path);
  if (r != 0)
    warn("rm %s", path);
  return r;
}


bool rmfile_recursive(const char* path) {
  int fd_limit = 64;
  return nftw(path, rmfile_recursive_cb, fd_limit, FTW_DEPTH | FTW_PHYS) == 0;
}


static void resolve_exe_path(const char* argv0) {
  char tmp1[PATH_MAX];

  _exe_path[0] = 0;
  _exe_path_init = true;

  if (*argv0 == '/') {
    // absolute path
    usize len = strlen(argv0);
    if (len < PATH_MAX)
      memcpy(_exe_path, argv0, len + 1);
  } else if (strchr(argv0, '/')) {
    // relative path
    if (getcwd(tmp1, PATH_MAX))
      path_join_resolve(_exe_path, tmp1, argv0);
  } else {
    // look in PATH
    const char* PATH = getenv("PATH");
    if (!PATH || strlen(PATH) >= PATH_MAX) {
      dlog("getenv(PATH)");
      // errno = ENOENT;
      return;
    }
    memcpy(tmp1, PATH, strlen(PATH));
    struct stat st;
    for (char* state = tmp1, *dir; (dir = strsep(&state, ":")) != NULL; ) {
      if (path_join_resolve(_exe_path, dir, argv0) && stat(_exe_path, &st) != 0)
        return;
    }
    *_exe_path = 0;
  }

  if (*_exe_path == 0)
    dlog("resolve_exe_path failed (argv0=%s)", argv0);
}


const char* get_exe_path(const char* argv0) {
  if (!_exe_path_init)
    resolve_exe_path(argv0);
  return *_exe_path ? _exe_path : NULL;
}


bool load_file(const char* filename, slice_t* result) {
  memset(result, 0, sizeof(*result));
  int fd = open(filename, O_RDONLY);
  if (fd < 0) {
    dlog("open");
    return false;
  }
  struct stat st;
  if (fstat(fd, &st) != 0) {
    dlog("fstat");
    return false;
  }

  if (st.st_size == 0)
    return true;

  void* p = mmap(0, (usize)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (p == MAP_FAILED) {
    dlog("MAP_FAILED");
    return false;
  }
  result->p = p;
  result->len = (usize)st.st_size;
  return true;
}


bool unload_file(slice_t* data) {
  if (data->len != 0 && munmap((void*)data->p, data->len) != 0)
    return false;
  data->p = NULL;
  data->len = 0;
  return true;
}


void* bumpalloc(bumpalloc_t* ma, usize size) {
  void* p = ma->next;
  ma->next += ALIGN(size, sizeof(void*));
  if (__builtin_expect(ma->next <= ma->end, true))
    return p;
  errno = ENOMEM;
  ma->next = ma->end;
  return NULL;
}


bool bumpalloc_resize(bumpalloc_t* ma, void* ptr, usize oldsize, usize newsize) {
  // only resize tail
  if (ptr != ma->next - oldsize)
    return false;
  if (oldsize > newsize) {
    ma->next -= oldsize - newsize;
  } else {
    ma->next += newsize - oldsize;
  }
  return true;
}


char* bumpalloc_strdup(bumpalloc_t* ma, const char* src) {
  usize len = strlen(src) + 1;
  char* dst = bumpalloc(ma, len);
  if (!dst)
    return NULL;
  return memcpy(dst, src, len);
}


bool slice_eq_cstr(slice_t s, const char* cstr) {
  usize len = strlen(cstr);
  return s.len == len && memcmp(s.p, cstr, len) == 0;
}


bool target_parse(target_t* target, const char* target_str, int flags) {
  // arch-sys[.ver][-suffix]
  memset(target, 0, sizeof(*target));
  const char* sysp = strchr(target_str, '-');
  if (!sysp) {
    if (!(flags & TARGET_PARSE_QUIET))
      warnx("invalid target \"%s\", missing system after architecture", target_str);
    return false;
  }
  sysp++;
  const char* endp = target_str + strlen(target_str);
  const char* verp = strchr(sysp, '.');
  const char* suffixp = strchr(sysp, '-');
  const char* sysend = verp ? verp : suffixp ? suffixp : endp;
  slice_t arch = {.p=target_str, .len=(usize)(sysp - 1 - target_str)};
  slice_t sys = {.p=sysp, .len=(usize)(sysend - sysp)};
  slice_t sysver = {0};
  if (verp) {
    sysver.p = ++verp;
    sysver.len = (usize)((suffixp ? suffixp : endp) - verp);
  };
  // dlog("target_parse(\"%s\") => (%.*s,%.*s,%.*s)", target_str,
  //   (int)arch.len, arch.cstr, (int)sys.len, sys.cstr, (int)sysver.len, sysver.cstr);

  if (!(flags & TARGET_PARSE_VALIDATE)) {
    char* archp = malloc(arch.len + 1);
    char* sysp = malloc(sys.len + 1);
    char* sysverp = malloc(sysver.len + 1);
    if (!archp || !sysp || !sysverp)
      return false;
    target->arch = memcpy(archp, arch.p, arch.len); archp[arch.len] = 0;
    target->sys = memcpy(sysp, sys.p, sys.len); sysp[sys.len] = 0;
    target->sysver = memcpy(sysverp, sysver.p, sysver.len); sysverp[sysver.len] = 0;
    if (suffixp && suffixp[1]) {
      target->suffix = strdup(suffixp + 1);
      assert(target->suffix != NULL);
    } else {
      target->suffix = "";
    }
    return true;
  }

  bool found_without_version = false;
  for (usize i = 0; i < supported_targets_count; i++) {
    const target_t* t = &supported_targets[i];
    if (slice_eq_cstr(arch, t->arch) && slice_eq_cstr(sys, t->sys)) {
      found_without_version = true;
      if (sysver.len == 0 || slice_eq_cstr(sysver, t->sysver)) {
        *target = *t;
        return true;
      }
    }
  }

  if (!(flags & TARGET_PARSE_QUIET)) {
    if (found_without_version) {
      warnx("unsupported target system version \"%.*s\" of target \"%.*s-%.*s\"",
        (int)sysver.len, sysver.cstr, (int)arch.len, arch.cstr, (int)sys.len, sys.cstr);
    } else {
      warnx("unknown target \"%s\"", target_str);
    }
  }
  return false;
}


int target_str(target_t target, char* dst, usize dstcap) {
  return snprintf(dst, dstcap, TARGET_FMT, TARGET_FMT_ARGS(target));
}


bool str_has_suffix(const char* subject, const char* suffix) {
  usize subject_len = strlen(subject);
  usize suffix_len = strlen(suffix);
  return (
    subject_len >= suffix_len &&
    memcmp(subject + (subject_len - suffix_len), suffix, suffix_len) == 0 );
}


void _array_dispose(array_t* a) {
  if (a->ptr)
    free(a->ptr);
  a->ptr = NULL;
  a->cap = 0;
  a->len = 0;
}


bool _array_grow(array_t* a, u32 elemsize, u32 extracap) {
  u32 newcap;
  if (a->cap == 0) {
    newcap = MAX_X(extracap, 32u);
  } else if (check_mul_overflow(a->cap, (u32)2, &newcap)) {
    return false;
  }
  usize newsize;
  if (check_mul_overflow((usize)newcap, (usize)elemsize, &newsize))
    return false;
  void* p = realloc(a->ptr, newsize);
  if (!p)
    return false;
  a->ptr = p;
  a->cap = newsize / elemsize;
  return true;
}


bool _array_reserve(array_t* a, u32 elemsize, u32 minavail) {
  u32 newlen;
  if (check_add_overflow(a->len, minavail, &newlen))
    return false;
  return newlen <= a->cap || _array_grow(a, elemsize, newlen - a->cap);
}


void* _array_alloc(array_t* a, u32 elemsize, u32 len) {
  if UNLIKELY(!_array_reserve(a, elemsize, len))
    return NULL;
  void* p = a->ptr + a->len*elemsize;
  a->len += len;
  return p;
}


void* _array_allocat(array_t* a, u32 elemsize, u32 i, u32 len) {
  assert(i <= a->len);
  if UNLIKELY(i > a->len || !_array_reserve(a, elemsize, len))
    return NULL;
  void* p = a->ptr + i*elemsize;
  if (i < a->len) {
    // examples:
    //   allocat [ 0 1 2 3 4 ] 5, 2 => [ 0 1 2 3 4 _ _ ]
    //   allocat [ 0 1 2 3 4 ] 1, 2 => [ 0 _ _ 1 2 3 4 ]
    //   allocat [ 0 1 2 3 4 ] 4, 2 => [ 0 1 2 3 _ _ 4 ]
    void* dst = a->ptr + (i + len)*elemsize;
    memmove(dst, p, (usize)((a->len - i) * elemsize));
  }
  a->len += len;
  return p;
}


#define ARRAY_ELEM_PTR(elemsize, a, i) ( (a)->ptr + ((usize)(elemsize) * (usize)(i)) )


void* _array_sorted_assign(
  array_t* a, u32 elemsize, const void* valptr, array_sorted_cmp_t cmpf, void* cmpctx)
{
  // binary search
  isize insert_at_index = 0;
  u32 mid, low = 0, high = a->len;
  while (low < high) {
    mid = (low + high) / 2;
    void* existing = ARRAY_ELEM_PTR(elemsize, a, mid);
    int cmp = cmpf(valptr, existing, cmpctx);
    if (cmp == 0)
      return existing;
    if (cmp < 0) {
      high = mid;
      insert_at_index = mid;
    } else {
      low = mid + 1;
      insert_at_index = mid+1;
    }
  }
  void* p = _array_allocat(a, elemsize, insert_at_index, 1);
  memset(p, 0, elemsize);
  return p;
}

// ———————————————————————————————————————————————————————————————————————————————————
// copy_merge

typedef struct {
  int flags;
} copy_merge_t;


static bool copy_merge_any(copy_merge_t* cm, const char* dst, const char* src);


static bool copy_merge_badtype(copy_merge_t* cm, const char* path) {
  errno = EINVAL;
  warnx("uncopyable file type: %s", path);
  return false;
}


static bool copy_merge_link(copy_merge_t* cm, const char* dst, const char* src) {
  char target[PATH_MAX];

  ssize_t len = readlink(src, target, sizeof(target));
  if (len >= PATH_MAX) {
    errno = EOVERFLOW;
    return false;
  }
  target[len] = '\0';

  if (cm->flags & COPY_MERGE_VERBOSE)
    printf("create symlink %s -> %s\n", relpath(NULL, dst), target);

  if (symlink(target, dst) == 0)
    return true;

  if ((cm->flags & COPY_MERGE_OVERWRITE) && errno == EEXIST) {
    if (unlink(dst)) {
      warn("unlink: %s", dst);
      return false;
    }
    if (symlink(target, dst) == 0)
      return true;
  }
  warn("symlink: %s", dst);
  return false;
}


static isize copy_fd_fd(int src_fd, int dst_fd, char* buf, usize bufsize) {
  isize wresid, wcount = 0;
  char *bufp;
  isize rcount = read(src_fd, buf, bufsize);
  if (rcount <= 0)
    return rcount;
  for (bufp = buf, wresid = rcount; ; bufp += wcount, wresid -= wcount) {
    wcount = write(dst_fd, bufp, wresid);
    if (wcount <= 0)
      break;
    if (wcount >= (isize)wresid)
      break;
  }
  return wcount < 0 ? wcount : rcount;
}


static bool copy_file(copy_merge_t* cm, const char* dst, const char* src) {
  int src_fd = -1, dst_fd = -1;

  if (cm->flags & COPY_MERGE_VERBOSE)
    printf("add file %s\n", relpath(NULL, dst));

again:
  errno = 0;

  #if defined(__APPLE__)
    if (clonefile(src, dst, /*flags*/0) == 0)
      goto end;
  #endif

  // TODO: look into using ioctl_ficlone or copy_file_range on linux

  if (errno != EEXIST) {
    // fall back to byte copying
    if ((src_fd = open(src, O_RDONLY, 0)) == -1)
      goto end;
    struct stat src_st;
    if (fstat(src_fd, &src_st) != 0)
      goto end;
    mode_t dst_mode = src_st.st_mode & ~(S_ISUID | S_ISGID);
    if ((dst_fd = open(dst, O_WRONLY|O_TRUNC|O_CREAT, dst_mode)) == -1)
      goto end;

    static char *buf = NULL; // WARNING! SINGLE-THREADED ONLY!
    if (!buf && (buf = malloc(4096)) == NULL)
      goto end;

    isize rcount;
    for (;;) {
      rcount = copy_fd_fd(src_fd, dst_fd, buf, 4096);
      if (rcount == 0)
        goto end;
      if (rcount < 0)
        break;
    }
  }

  if (errno == EEXIST && (cm->flags & COPY_MERGE_OVERWRITE)) {
    unlink(dst);
    goto again;
  }

end:
  if (src_fd != -1) close(src_fd);
  if (dst_fd != -1) close(dst_fd);
  if (errno)
    warn("%s", dst);
  return errno == 0;
}


static bool copy_merge_dir(
  copy_merge_t* cm, const char* dst, const char* src, mode_t mode)
{
  char tmp[PATH_MAX];
  char tmp2[PATH_MAX];

  DIR* dirp = opendir(src);
  if (!dirp)
    return false;

  if (mode == 0) {
    struct stat st;
    if (fstat(dirfd(dirp), &st) != 0)
      return false;
    mode = st.st_mode;
  }
  mode &= S_IRWXU|S_IRWXG|S_IRWXO; //|S_ISUID|S_ISGID|S_ISVTX;

  if ((cm->flags & COPY_MERGE_VERBOSE) && !isdir(dst))
    printf("creating directory %s\n", relpath(NULL, dst));

  if (!mkdirs(dst, mode))
    return false;

  struct dirent ent;
  struct dirent* result;
  bool ok = true;
  while (readdir_r(dirp, &ent, &result) == 0 && result && ok) {
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
    if (!path_join(tmp, dst, ent.d_name))
      return false;
    if (!path_join(tmp2, src, ent.d_name))
      return false;
    #if defined(__APPLE__) || defined(__linux__)
      int dtype = ent.d_type;
    #else
      int dtype = 0;
    #endif
    switch (dtype) {
      case DT_REG: ok = copy_file(cm, tmp, tmp2); break;
      case DT_LNK: ok = copy_merge_link(cm, tmp, tmp2); break;
      case DT_DIR: ok = copy_merge_dir(cm, tmp, tmp2, 0); break;
      case 0:      ok = copy_merge_any(cm, tmp, tmp2); break;
      default:     return copy_merge_badtype(cm, tmp2);
    }
  }

  closedir(dirp);
  return ok;
}


static bool copy_merge_any(copy_merge_t* cm, const char* dst, const char* src) {
  struct stat st;
  if (lstat(src, &st) != 0)
    return false;
  if (S_ISREG(st.st_mode)) return copy_file(cm, dst, src);
  if (S_ISLNK(st.st_mode)) return copy_merge_link(cm, dst, src);
  if (S_ISDIR(st.st_mode)) return copy_merge_dir(cm, dst, src, st.st_mode);
  return copy_merge_badtype(cm, src);
}


bool copy_merge(const char* srcpath, const char* dstpath, int flags) {
  copy_merge_t cm = { .flags=flags };
  return copy_merge_any(&cm, dstpath, srcpath);
}


// ———————————————————————————————————————————————————————————————————————————————————
// SHA-256 aka SHA-2 implementation by Alain Mosnier (public domain)
// https://github.com/amosnier/sha-2

static inline u32 right_rot(u32 value, unsigned int count) {
  return value >> count | value << (32 - count);
}

static inline void sha256_consume_chunk(u32 *h, const u8 *p) {
  unsigned i, j;
  u32 ah[8];
  for (i = 0; i < 8; i++)
    ah[i] = h[i];
  u32 w[16];
  for (i = 0; i < 4; i++) {
    for (j = 0; j < 16; j++) {
      if (i == 0) {
        w[j] =
            (u32)p[0] << 24 | (u32)p[1] << 16 | (u32)p[2] << 8 | (u32)p[3];
        p += 4;
      } else {
        const u32 s0 = right_rot(w[(j + 1) & 0xf], 7) ^ right_rot(w[(j + 1) & 0xf], 18) ^
                (w[(j + 1) & 0xf] >> 3);
        const u32 s1 = right_rot(w[(j + 14) & 0xf], 17) ^
                right_rot(w[(j + 14) & 0xf], 19) ^ (w[(j + 14) & 0xf] >> 10);
        w[j] = w[j] + s0 + w[(j + 9) & 0xf] + s1;
      }
      const u32 s1 = right_rot(ah[4], 6) ^ right_rot(ah[4], 11) ^ right_rot(ah[4], 25);
      const u32 ch = (ah[4] & ah[5]) ^ (~ah[4] & ah[6]);

      static const u32 k[] = {
          0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
          0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
          0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
          0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
          0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
          0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
          0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
          0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
          0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
          0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
          0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 };

      const u32 temp1 = ah[7] + s1 + ch + k[i << 4 | j] + w[j];
      const u32 s0 = right_rot(ah[0], 2) ^ right_rot(ah[0], 13) ^ right_rot(ah[0], 22);
      const u32 maj = (ah[0] & ah[1]) ^ (ah[0] & ah[2]) ^ (ah[1] & ah[2]);
      const u32 temp2 = s0 + maj;

      ah[7] = ah[6];
      ah[6] = ah[5];
      ah[5] = ah[4];
      ah[4] = ah[3] + temp1;
      ah[3] = ah[2];
      ah[2] = ah[1];
      ah[1] = ah[0];
      ah[0] = temp1 + temp2;
    }
  }
  for (i = 0; i < 8; i++)
    h[i] += ah[i];
}

void sha256_init(sha256_t *sha_256, u8 hash[SHA256_SUM_SIZE]) {
  sha_256->hash = hash;
  sha_256->chunk_pos = sha_256->chunk;
  sha_256->space_left = SHA256_CHUNK_SIZE;
  sha_256->total_len = 0;
  sha_256->h[0] = 0x6a09e667;
  sha_256->h[1] = 0xbb67ae85;
  sha_256->h[2] = 0x3c6ef372;
  sha_256->h[3] = 0xa54ff53a;
  sha_256->h[4] = 0x510e527f;
  sha_256->h[5] = 0x9b05688c;
  sha_256->h[6] = 0x1f83d9ab;
  sha_256->h[7] = 0x5be0cd19;
}

void sha256_write(sha256_t *sha_256, const void *data, usize len) {
  sha_256->total_len += len;
  const u8 *p = data;
  while (len > 0) {
    if (sha_256->space_left == SHA256_CHUNK_SIZE && len >= SHA256_CHUNK_SIZE) {
      sha256_consume_chunk(sha_256->h, p);
      len -= SHA256_CHUNK_SIZE;
      p += SHA256_CHUNK_SIZE;
      continue;
    }
    const usize consumed_len = len < sha_256->space_left ? len : sha_256->space_left;
    memcpy(sha_256->chunk_pos, p, consumed_len);
    sha_256->space_left -= consumed_len;
    len -= consumed_len;
    p += consumed_len;
    if (sha_256->space_left == 0) {
      sha256_consume_chunk(sha_256->h, sha_256->chunk);
      sha_256->chunk_pos = sha_256->chunk;
      sha_256->space_left = SHA256_CHUNK_SIZE;
    } else {
      sha_256->chunk_pos += consumed_len;
    }
  }
}

void sha256_close(sha256_t *sha_256) {
  u8 *pos = sha_256->chunk_pos;
  usize space_left = sha_256->space_left;
  const usize kTotalLenLen = 8;
  u32 *const h = sha_256->h;
  *pos++ = 0x80;
  --space_left;
  if (space_left < kTotalLenLen) {
    memset(pos, 0x00, space_left);
    sha256_consume_chunk(h, sha_256->chunk);
    pos = sha_256->chunk;
    space_left = SHA256_CHUNK_SIZE;
  }
  const usize left = space_left - kTotalLenLen;
  memset(pos, 0x00, left);
  pos += left;
  usize len = sha_256->total_len;
  pos[7] = (u8)(len << 3);
  len >>= 5;
  int i;
  for (i = 6; i >= 0; --i) {
    pos[i] = (u8)len;
    len >>= 8;
  }
  sha256_consume_chunk(h, sha_256->chunk);
  int j;
  u8 *const hash = sha_256->hash;
  for (i = 0, j = 0; i < 8; i++) {
    hash[j++] = (u8)(h[i] >> 24);
    hash[j++] = (u8)(h[i] >> 16);
    hash[j++] = (u8)(h[i] >> 8);
    hash[j++] = (u8)h[i];
  }
}

// ———————————————————————————————————————————————————————————————————————————————————
// quick sort
// void lb_qsort(
//   void* base, usize nmemb, usize size,
//   int(*cmp)(const void* x, const void* y, void* ctx),
//   void* ctx);
//
// qsort_r is not a libc standard function; its signature differs:
//   ISO TR 24731-1
//     errno_t qsort_s(
//       void* base, usize nmemb, usize size,
//       int (*cmp)(const void* x, const void* y, void* ctx),
//       void* ctx);
//   GNU libc, musl libc (and probably all other Linux-oriented libcs)
//     void qsort_r(
//       void* base, usize nmemb, usize size,
//       int (*cmp)(const void* x, const void* y, void* ctx),
//       void* ctx);
//   Microsoft Windows
//     void qsort_s(
//       void* base, usize nmemb, usize size,
//       int (__cdecl*cmp)(void* ctx, const void* x, const void* y),  ← ctx position
//       void* ctx);
//   BSD
//     void qsort_r(
//       void* base, usize nmemb, usize size,
//       void* ctx,                                             ← ctx position
//       int (*cmp)(void* ctx, const void* x, const void* y));  ← cmp & ctx position
//
// For this reason we use qsort from musl.
/* Copyright (C) 2011 by Valentin Ochs
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

/*
Minor changes by Rich Felker for integration in musl, 2011-04-27.

Minor changes by Rasmus Andersson for integration in rsm, 2022-02-27.
 - Comparison with matching signed/unsigned integers
 - Use of __builtin_ctz (rsm_ctz) instead of a_ctz_{32,64} asm implementations

Smoothsort, an adaptive variant of Heapsort.  Memory usage: O(1).
Run time: Worst case O(n log n), close to O(n) in the mostly-sorted case.
*/

static inline int pntz(size_t p[2]) {
  int r = lb_ctz(p[0] - 1);
  if(r != 0 || (r = 8*sizeof(size_t) + lb_ctz(p[1])) != 8*sizeof(size_t)) {
    return r;
  }
  return 0;
}

static void cycle(size_t width, unsigned char* ar[], int n) {
  unsigned char tmp[256];
  size_t l;
  int i;

  if(n < 2) {
    return;
  }

  ar[n] = tmp;
  while(width) {
    l = sizeof(tmp) < width ? sizeof(tmp) : width;
    memcpy(ar[n], ar[0], l);
    for(i = 0; i < n; i++) {
      memcpy(ar[i], ar[i + 1], l);
      ar[i] += l;
    }
    width -= l;
  }
}

/* shl() and shr() need n > 0 */
static inline void shl(size_t p[2], int n) {
  if(n >= (int)(8 * sizeof(size_t))) {
    n -= (int)(8 * sizeof(size_t));
    p[1] = p[0];
    p[0] = 0;
  }
  p[1] <<= n;
  p[1] |= p[0] >> (sizeof(size_t) * 8 - n);
  p[0] <<= n;
}

static inline void shr(size_t p[2], int n) {
  if(n >= (int)(8 * sizeof(size_t))) {
    n -= (int)(8 * sizeof(size_t));
    p[0] = p[1];
    p[1] = 0;
  }
  p[0] >>= n;
  p[0] |= p[1] << (sizeof(size_t) * 8 - n);
  p[1] >>= n;
}

static void sift(
  unsigned char *head, size_t width, lb_qsort_cmp cmp,
  void *arg, int pshift, size_t lp[])
{
  unsigned char *rt, *lf;
  unsigned char *ar[14 * sizeof(size_t) + 1];
  int i = 1;

  ar[0] = head;
  while(pshift > 1) {
    rt = head - width;
    lf = head - width - lp[pshift - 2];

    if(cmp(ar[0], lf, arg) >= 0 && cmp(ar[0], rt, arg) >= 0) {
      break;
    }
    if(cmp(lf, rt, arg) >= 0) {
      ar[i++] = lf;
      head = lf;
      pshift -= 1;
    } else {
      ar[i++] = rt;
      head = rt;
      pshift -= 2;
    }
  }
  cycle(width, ar, i);
}

static void trinkle(
  unsigned char *head, size_t width, lb_qsort_cmp cmp,
  void *arg, size_t pp[2], int pshift, int trusty, size_t lp[])
{
  unsigned char *stepson,
                *rt, *lf;
  size_t p[2];
  unsigned char *ar[14 * sizeof(size_t) + 1];
  int i = 1;
  int trail;

  p[0] = pp[0];
  p[1] = pp[1];

  ar[0] = head;
  while(p[0] != 1 || p[1] != 0) {
    stepson = head - lp[pshift];
    if(cmp(stepson, ar[0], arg) <= 0) {
      break;
    }
    if(!trusty && pshift > 1) {
      rt = head - width;
      lf = head - width - lp[pshift - 2];
      if(cmp(rt, stepson, arg) >= 0 || cmp(lf, stepson, arg) >= 0) {
        break;
      }
    }

    ar[i++] = stepson;
    head = stepson;
    trail = pntz(p);
    shr(p, trail);
    pshift += trail;
    trusty = 0;
  }
  if(!trusty) {
    cycle(width, ar, i);
    sift(head, width, cmp, arg, pshift, lp);
  }
}

void lb_qsort(void *base, size_t nel, size_t width, lb_qsort_cmp cmp, void* arg) {
  size_t lp[12*sizeof(size_t)];
  size_t i, size = width * nel;
  unsigned char *head, *high;
  size_t p[2] = {1, 0};
  int pshift = 1;
  int trail;

  if (!size) return;

  head = base;
  high = head + size - width;

  /* Precompute Leonardo numbers, scaled by element width */
  for(lp[0]=lp[1]=width, i=2; (lp[i]=lp[i-2]+lp[i-1]+width) < size; i++);

  while(head < high) {
    if((p[0] & 3) == 3) {
      sift(head, width, cmp, arg, pshift, lp);
      shr(p, 2);
      pshift += 2;
    } else {
      if ((isize)lp[pshift - 1] >= (isize)(high - head)) {
        trinkle(head, width, cmp, arg, p, pshift, 0, lp);
      } else {
        sift(head, width, cmp, arg, pshift, lp);
      }

      if(pshift == 1) {
        shl(p, 1);
        pshift = 0;
      } else {
        shl(p, pshift - 1);
        pshift = 1;
      }
    }

    p[0] |= 1;
    head += width;
  }

  trinkle(head, width, cmp, arg, p, pshift, 0, lp);

  while(pshift != 1 || p[0] != 1 || p[1] != 0) {
    if(pshift <= 1) {
      trail = pntz(p);
      shr(p, trail);
      pshift += trail;
    } else {
      shl(p, 2);
      pshift -= 2;
      p[0] ^= 7;
      shr(p, 1);
      trinkle(head - lp[pshift] - width, width, cmp, arg, p, pshift + 1, 1, lp);
      shl(p, 1);
      p[0] |= 1;
      trinkle(head - width, width, cmp, arg, p, pshift, 1, lp);
    }
    head -= width;
  }
}


