// SPDX-License-Identifier: Apache-2.0
#include "llvmboxlib.h"
#ifdef __APPLE__
  #include <sys/clonefile.h>
#endif

// TODO: consider rewriting this using nftw


static bool copy_merge_badtype(copy_merge_t* cm, const char* path) {
  errno = EINVAL;
  warnx("uncopyable file type: %s", path);
  return false;
}


static bool copy_merge_link(copy_merge_t* cm, const char* dst, const char* src) {
  char tmp[PATH_MAX];
  ssize_t len = readlink(src, tmp, sizeof(tmp));
  if (len >= PATH_MAX) {
    errno = EOVERFLOW;
    return false;
  }
  tmp[len] = '\0';
  if (symlink(tmp, dst) == 0)
    return true;
  if (cm->overwrite && errno == EEXIST) {
    if (unlink(dst)) {
      warn("unlink: %s", dst);
      return false;
    }
    if (symlink(tmp, dst) == 0)
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

  if (errno == EEXIST && cm->overwrite) {
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
      case 0:      ok = copy_merge(cm, tmp, tmp2); break;
      default:     return copy_merge_badtype(cm, tmp2);
    }
  }

  closedir(dirp);
  return ok;
}


bool copy_merge(copy_merge_t* cm, const char* dst, const char* src) {
  struct stat st;
  if (lstat(src, &st) != 0)
    return false;
  if (S_ISREG(st.st_mode)) return copy_file(cm, dst, src);
  if (S_ISLNK(st.st_mode)) return copy_merge_link(cm, dst, src);
  if (S_ISDIR(st.st_mode)) return copy_merge_dir(cm, dst, src, st.st_mode);
  return copy_merge_badtype(cm, src);
}
