// SHA-256
#pragma once
ASSUME_NONNULL_BEGIN

#define SHA256_CHUNK_SIZE 64

typedef struct SHA256 {
  u8*   hash;
  u8    chunk[SHA256_CHUNK_SIZE];
  u8*   chunk_pos;
  usize space_left;
  usize total_len;
  u32   h[8];
} SHA256;

void sha256_init(SHA256* state, u8 hash_storage[32]);
void sha256_write(SHA256* state, const void* data, usize len);
void sha256_close(SHA256* state);
void sha256_data(u8 result[32], const u8* data, usize len);

ASSUME_NONNULL_END
