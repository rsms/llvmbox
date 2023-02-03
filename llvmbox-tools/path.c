// SPDX-License-Identifier: Apache-2.0
#include "llvmbox-tools.h"


bool join_path(char result[PATH_MAX], const char* path1, const char* path2) {
  if (snprintf(result, PATH_MAX, "%s/%s", path1, path2) >= PATH_MAX) {
    errno = EOVERFLOW;
    return false;
  }
  return true;
}


bool resolve_path(char result[PATH_MAX], struct stat* st, const char* path) {
  assert(strlen(path) < PATH_MAX);
  return realpath(path, result) && stat(result, st) == 0;
}


bool resolve_path2(char result[PATH_MAX], const char* path1, const char* path2) {
  char tmp[PATH_MAX];
  struct stat st;
  if (!join_path(tmp, path1, path2))
    return false;
  return resolve_path(result, &st, tmp);
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
