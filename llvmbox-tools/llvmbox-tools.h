#pragma once

#define _GNU_SOURCE
#define _BSD_SOURCE
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

typedef int8_t             i8;
typedef uint8_t            u8;
typedef int16_t            i16;
typedef uint16_t           u16;
typedef int32_t            i32;
typedef uint32_t           u32;
typedef signed long long   i64;
typedef unsigned long long u64;
typedef size_t             usize;
typedef ssize_t            isize;
typedef intptr_t           intptr;
typedef uintptr_t          uintptr;
typedef float              f32;
typedef double             f64;

#ifdef DEBUG
  #include <assert.h>
  #define dlog(fmt, args...) ( \
    fprintf(stderr, "\e[1;34m▍\e[0m" fmt " \e[2m(%s %s:%d)\e[0m\n", ##args, \
      __FUNCTION__, __FILE__, __LINE__), \
    fflush(stderr) )
#else
  #define dlog(...) ((void)0)
  #ifndef assert
    #define assert(x) ((void)0)
  #endif
#endif

#ifndef countof
  #define countof(x) ((sizeof(x)/sizeof(0[x])) / ((usize)(!(sizeof(x) % sizeof(0[x])))))
#endif

// path.c
bool join_path(char result[PATH_MAX], const char* path1, const char* path2);
bool resolve_path(char result[PATH_MAX], struct stat* st, const char* path);
bool resolve_path2(char result[PATH_MAX], const char* path1, const char* path2);
bool mkdirs(const char *path, mode_t mode);

// copy_merge.c
typedef struct {
  bool overwrite; // if a file exists, replace it instead of reporting an error
} copy_merge_t;
bool copy_merge(copy_merge_t*, const char* dst, const char* src);
