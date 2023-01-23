/**
 * Copyright (C) 2017  Niklas Rosenstein
 * Copyright (C) 2014  PHPdev32
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * \file pbzx.c
 * \created 2014-06-20
 */

#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lzma.h>
#include <xar/xar.h>

#define XBSZ 4 * 1024
#define ZBSZ 1024 * XBSZ
#define VERSION "1.0.2"

/* Structure to hold the command-line options. */
struct options {
    bool stdin;    /* True if data should be read from stdin. */
    bool noxar;    /* The input data is not a XAR archive but the pbzx Payload. */
    bool help;     /* Print usage with details and exit. */
    bool version;  /* Print version and exit. */
};

/* Prints usage information and exit. Optionally, displays an error message and
 * exits with an error code. */
static void usage(char const* error) {
    fprintf(stderr, "usage: pbzx [-v] [-h] [-n] [-] [filename]\n");
    if (error) {
        fprintf(stderr, "error: %s\n", error);
        exit(EINVAL);
    }
    fprintf(stderr,
        "\n"
        "pbzx v" VERSION " stream parser\n"
        "https://github.com/NiklasRosenstein/pbzx\n"
        "\n"
        "Licensed under GNU GPL v3.\n"
        "Copyright (C) 2017  NiklasRosenstein\n"
        "Copyright (C) 2015  PHPdev32\n"
        "\n"
    );
    exit(0);
}

/* Prints the version and exits. */
static void version() {
    printf("pbzx v" VERSION "\n");
    exit(0);
}

/* Parses command-line flags into the #options structure and adjusts the
 * argument count and values on the fly to remain only positional arguments. */
static void parse_args(int* argc, char const** argv, struct options* opts) {
    for (int i = 0; i < *argc; ++i) {
        /* Skip arguments that are not flags. */
        if (argv[i][0] != '-') continue;
        /* Match available arguments. */
        if      (strcmp(argv[i], "-")  == 0) opts->stdin = true;
        else if (strcmp(argv[i], "-n") == 0) opts->noxar = true;
        else if (strcmp(argv[i], "-h") == 0) opts->help = true;
        else if (strcmp(argv[i], "-v") == 0) opts->version = true;
        else usage("unrecognized flag");
        /* Move all remaining arguments to the front. */
        for (int j = 0; j < (*argc-1); ++j) {
            argv[j] = argv[j+1];
        }
        (*argc)--;
    }
}

static inline uint32_t min(uint32_t a, uint32_t b) {
    return (a < b ? a : b);
}

/* Possible types for the #stream structure. */
enum {
    STREAM_XAR = 1,
    STREAM_FP
};

/* Generic datastructure that can represent a streamed file in a XAR archive
 * or a C FILE pointer. The stream is initialized respectively depending on
 * the command-line flags. */
struct stream {
    int type;       /* One of #STREAM_XAR and #STREAM_FP. */
    xar_t xar;      /* Only valid if #type == #STREAM_XAR. */
    xar_stream xs;  /* Only valid if #type == #STREAM_XAR. */
    FILE* fp;       /* Only valid if #type == #STREAM_FP. */
};

/* Initialize an empty stream. */
static void stream_init(struct stream* s) {
    s->type = 0;
    s->xar = NULL;
    memset(&s->xs, 0, sizeof(s->xs));
    s->fp = NULL;
}

/* Open a stream of the specified type and filename. */
static bool stream_open(struct stream* s, int type, const char* filename) {
    stream_init(s);
    s->type = type;
    switch (type) {
        case STREAM_XAR: {
            s->xar = xar_open(filename, READ);
            if (!s->xar) return false;
            xar_iter_t i = xar_iter_new();
            xar_file_t f = xar_file_first(s->xar, i);
            char* path = NULL;
            /* Find the Payload file in the archive. */
            while (strncmp((path = xar_get_path(f)), "Payload", 7) &&
                   (f = xar_file_next(i))) {
                free(path);
            }
            free(path);
            xar_iter_free(i);
            if (!f) return false;  /* No Payload. */
            if (xar_verify(s->xar, f) != XAR_STREAM_OK) return false;  /* File verification failed. */
            if (xar_extract_tostream_init(s->xar, f, &s->xs) != XAR_STREAM_OK) return false;  /* XAR Stream init failed. */
            return true;
        }
        case STREAM_FP: {
            s->fp = fopen(filename, "rb");
            if (!s->fp) return false;  /* File can not be opened. */
            return true;
        }
        default: return false;
    }
}

/* Close an opened stream. After this function, the stream is initialized
 * to an empty stream object. */
static void stream_close(struct stream* s) {
    switch (s->type) {
        case STREAM_XAR:
            xar_extract_tostream_end(&s->xs);
            xar_close(s->xar);
            break;
        case STREAM_FP:
            fclose(s->fp);
            break;
    }
    stream_init(s);
}

/* Read bytes from the stream into a buffer. Returns the number of bytes
 * that have been put into the buffer. */
static uint32_t stream_read(char* buf, uint32_t size, struct stream* s) {
    if (!s) return 0;
    switch (s->type) {
        case STREAM_XAR:
        default:
            s->xs.next_out = buf;
            s->xs.avail_out = size;
            while (s->xs.avail_out) {
                if (xar_extract_tostream(&s->xs) != XAR_STREAM_OK) {
                    return size - s->xs.avail_out;
                }
            }
            return size;
        case STREAM_FP:
            return fread(buf, size, 1, s->fp);
    }
    abort();
}

/* Reads a #uint64_t from the stream. */
static inline uint64_t stream_read_64(struct stream* stream) {
    char buf[8];
    stream_read(buf, 8, stream);
    return __builtin_bswap64(*(uint64_t*) buf);
}

static inline size_t cpio_out(char *buffer, size_t size) {
    size_t c = 0;
    while (c < size) {
        c+= fwrite(buffer + c, 1, size - c, stdout);
    }
    return c;
}

int main(int argc, const char** argv) {
    /* Parse and validate command-line flags and arguments. */
    struct options opts = {0};
    parse_args(&argc, argv, &opts);
    if (opts.version) version();
    if (opts.help) usage(NULL);
    if (!opts.stdin && argc < 2)
        usage("missing filename argument");
    else if ((!opts.stdin && argc > 2) || (opts.stdin && argc > 1))
        usage("unhandled positional argument(s)");

    char const* filename = NULL;
    if (argc >= 2) filename = argv[1];

    /* Open a stream to the payload. */
    struct stream stream;
    stream_init(&stream);
    bool success = false;
    if (opts.stdin) {
        stream.type = STREAM_FP;
        stream.fp = stdin;
        success = true;
    }
    else if (opts.noxar) {
        success = stream_open(&stream, STREAM_FP, filename);
    }
    else {
        success = stream_open(&stream, STREAM_XAR, filename);
    }
    if (!success) {
        fprintf(stderr, "failed to open: %s\n", filename);
        return 1;
    }

    /* Start extracting the payload data. */
    char xbuf[XBSZ];
    char* zbuf = malloc(ZBSZ);

    /* Make sure we have a pbxz stream. */
    stream_read(xbuf, 4, &stream);
    if (strncmp(xbuf, "pbzx", 4) != 0) {
        fprintf(stderr, "not a pbzx stream\n");
        return 1;
    }

    /* Initialize LZMA. */
    uint64_t length = 0;
    uint64_t flags = stream_read_64(&stream);
    uint64_t last = 0;
    lzma_stream zs = LZMA_STREAM_INIT;
    if (lzma_stream_decoder(&zs, UINT64_MAX, LZMA_CONCATENATED) != LZMA_OK) {
        fprintf(stderr, "LZMA init failed\n");
        return 1;
    }

    /* Read LZMA chunks. */
    while (flags & 1 << 24) {
        flags = stream_read_64(&stream);
        length = stream_read_64(&stream);
        char plain = (length == 0x1000000);
        stream_read(xbuf, min(XBSZ, (uint32_t) length), &stream);
        /* Validate the header. */
        if (!plain && strncmp(xbuf, "\xfd""7zXZ\0", 6) != 0) {
            fprintf(stderr, "Header is not <FD>7zXZ<00>\n");
            return 1;
        }
        while (length) {
            if (plain) {
                cpio_out(xbuf, min(XBSZ, length));
            }
            else {
                zs.next_in = (typeof(zs.next_in)) xbuf;
                zs.avail_in = min(XBSZ, length);
                while (zs.avail_in) {
                    zs.next_out = (typeof(zs.next_out)) zbuf;
                    zs.avail_out = ZBSZ;
                    if (lzma_code(&zs, LZMA_RUN) != LZMA_OK) {
                        fprintf(stderr, "LZMA failure");
                        return 1;
                    }
                    cpio_out(zbuf, ZBSZ - zs.avail_out);
                }
            }
            length -= last = min(XBSZ, length);
            stream_read(xbuf, min(XBSZ, (uint32_t)length), &stream);
        }
        if (!plain && strncmp(xbuf + last-2, "YZ", 2) != 0) {
            fprintf(stderr, "Footer is not YZ");
            return 1;
        }
    }
    free(zbuf);
    lzma_end(&zs);
    if (!opts.stdin) stream_close(&stream);
    return 0;
}
