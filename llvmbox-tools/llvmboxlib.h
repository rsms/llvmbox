#pragma once

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

#define _GNU_SOURCE
#define _BSD_SOURCE
#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <libgen.h>
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
    fprintf(stderr, "\e[1;34m▍\e[0m" fmt " \e[2m(%s:%d)\e[0m\n", ##args, \
      __FILE__, __LINE__), \
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

#define MAX_X(a,b)  ( (a) > (b) ? (a) : (b) )
#define MIN_X(a,b)  ( (a) < (b) ? (a) : (b) )

// T ALIGN<T>(T x, anyuint a) rounds up x to nearest a.
// a must be a constant power of two.
#define ALIGN(x,a) ( \
  ( (x) + ((__typeof__(x))(a) - 1) ) & ~((__typeof__(x))(a) - 1) )

#define UNLIKELY(x) (__builtin_expect((bool)(x), false))

static inline __attribute__((warn_unused_result)) bool __must_check_unlikely(
  bool unlikely)
{
  return UNLIKELY(unlikely);
}

#define check_add_overflow(a, b, dst) __must_check_unlikely(({  \
  __typeof__(a) a__ = (a);                 \
  __typeof__(b) b__ = (b);                 \
  __typeof__(dst) dst__ = (dst);           \
  (void) (&a__ == &b__);                   \
  (void) (&a__ == dst__);                  \
  __builtin_add_overflow(a__, b__, dst__); \
}))

#define check_sub_overflow(a, b, dst) __must_check_unlikely(({  \
  __typeof__(a) a__ = (a);                 \
  __typeof__(b) b__ = (b);                 \
  __typeof__(dst) dst__ = (dst);           \
  (void) (&a__ == &b__);                   \
  (void) (&a__ == dst__);                  \
  __builtin_sub_overflow(a__, b__, dst__); \
}))

#define check_mul_overflow(a, b, dst) __must_check_unlikely(({  \
  __typeof__(a) a__ = (a);                 \
  __typeof__(b) b__ = (b);                 \
  __typeof__(dst) dst__ = (dst);           \
  (void) (&a__ == &b__);                   \
  (void) (&a__ == dst__);                  \
  __builtin_mul_overflow(a__, b__, dst__); \
}))

typedef struct {
  u8* ptr;
  u32 cap, len; // count of T items (not bytes)
} array_t;

#define array_type(T) struct { T* v; u32 cap, len; }

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
  const char* suffix; // any dirname suffix for search, e.g. "libc"
} target_t;

typedef array_type(target_t) targetarray_t;

typedef struct {
  void* start;
  void* end;
  void* next;
} bumpalloc_t;

#define SHA256_SUM_SIZE   32
#define SHA256_CHUNK_SIZE 64

typedef struct { union { u8 data[SHA256_SUM_SIZE]; void* _alignme; }; } sha256sum_t;

typedef struct {
  u8*   hash;
  u8    chunk[SHA256_CHUNK_SIZE];
  u8*   chunk_pos;
  usize space_left;
  usize total_len;
  u32   h[8];
} sha256_t;

#define LB_PLUS_ONE(...) + 1lu
enum { SUPPORTED_TARGETS_COUNT = (0lu FOR_EACH_SUPPORTED_TARGET(LB_PLUS_ONE)) };

extern const target_t    supported_targets[];
extern const char* const supported_target_triples[];

#define TARGET_FMT "%s-%s%s%s%s%s"
#define TARGET_FMT_ARGS(target) \
  (target).arch, \
  (target).sys, \
  (*(target).sysver ? "." : ""), \
  (*(target).sysver ? (target).sysver : ""), \
  (*(target).suffix ? "-" : ""), \
  (*(target).suffix ? (target).suffix : "")

// int lb_ctz(ANYUINT x) counts trailing zeroes in x,
// starting at the least significant bit position.
// If x is 0, the result is undefined.
#define lb_ctz(x) _Generic((x), \
  i8:   __builtin_ctz,   u8:    __builtin_ctz, \
  i16:  __builtin_ctz,   u16:   __builtin_ctz, \
  i32:  __builtin_ctz,   u32:   __builtin_ctz, \
  long: __builtin_ctzl,  unsigned long: __builtin_ctzl, \
  long long:  __builtin_ctzll, unsigned long long:   __builtin_ctzll)(x)

void* bumpalloc(bumpalloc_t* ma, usize size);
bool bumpalloc_resize(bumpalloc_t* ma, void* ptr, usize oldsize, usize newsize);
char* bumpalloc_strdup(bumpalloc_t* ma, const char* src);

int path_clean(char result[PATH_MAX], const char* restrict path);
int path_cleann(char result[PATH_MAX], const char* restrict path, usize len);
int path_join(char result[PATH_MAX], const char* path1, const char* path2);
char* path_join_dup(bumpalloc_t* ma, const char* path1, const char* path2);
bool path_resolve(char result[PATH_MAX], const char* path);
bool path_join_resolve(char result[PATH_MAX], const char* path1, const char* path2);
usize path_common_prefix_len(const char* a, const char* b);
const char* relpath(const char* parent, const char* path);
bool isdir(const char* path);
bool mkdirs(const char *path, mode_t mode);
bool rmfile_recursive(const char* path);
const char* get_exe_path(const char* argv0);

bool load_file(const char* filename, slice_t* result);
bool unload_file(slice_t* data);

bool slice_eq_cstr(slice_t s, const char* cstr);

#define TARGET_PARSE_QUIET    (1<<0)  // don't print errors
#define TARGET_PARSE_VALIDATE (1<<1)  // validate against supported_targets
bool target_parse(target_t* target_out, const char* target_str, int flags);
int target_str(target_t target, char* dst, usize dstcap); // e.g. "arch-sys.ver-suffix"

void sha256_init(sha256_t* state, u8 hash_storage[SHA256_SUM_SIZE]);
void sha256_write(sha256_t* state, const void* data, usize len);
void sha256_close(sha256_t* state);

bool str_has_suffix(const char* subject, const char* suffix);

#define array_dispose(a)  _array_dispose((array_t*)(a))
#define array_at(T, a, i)  ( ((T*)((array_t*)(a))->ptr)[i] )
#define array_alloc(T, a, len) \
  ( (T*)_array_alloc((array_t*)(a), sizeof(T), (len)) )
#define array_allocat(T, a, i, len) \
  ( (T*)_array_allocat((array_t*)(a), sizeof(T), (i), (len)) )
#define array_push(T, a, val) ({ \
  array_t* __a = (array_t*)(a); \
  ( __a->len >= __a->cap && UNLIKELY(!_array_grow(__a, sizeof(T), 1)) ) ? false : \
    ( ( (T*)__a->ptr )[__a->len++] = (val), true ); \
})
// T* array_sorted_assign(T, array_t* a, T* vptr, array_sorted_cmp_t cmpf, void* cmpctx)
#define array_sorted_assign(T, a, valptr, cmpf, cmpctx) \
  (T*)_array_sorted_assign((array_t*)(a), sizeof(T), (valptr), (cmpf), (cmpctx))

void _array_dispose(array_t* a);
bool _array_grow(array_t* a, u32 elemsize, u32 extracap);
bool _array_reserve(array_t* a, u32 elemsize, u32 minavail);
void* _array_alloc(array_t* a, u32 elemsize, u32 len);
void* _array_allocat(array_t* a, u32 elemsize, u32 i, u32 len);

typedef int(*array_sorted_cmp_t)(const void* aptr, const void* bptr, void* ctx);
void* _array_sorted_assign(
  array_t* a, u32 elemsize, const void* valptr, array_sorted_cmp_t cmpf, void* cmpctx);

// lb_qsort is qsort_r aka qsort_s
typedef int(*lb_qsort_cmp)(const void* x, const void* y, void* ctx);
void lb_qsort(void* base, usize nmemb, usize width, lb_qsort_cmp cmp, void* ctx);

#define COPY_MERGE_OVERWRITE (1<<0)
#define COPY_MERGE_VERBOSE   (1<<1)
bool copy_merge(const char* srcpath, const char* dstpath, int flags);
