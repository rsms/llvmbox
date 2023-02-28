# options:
#   V[ERBOSE]=1  Print commands as they execute
#   DEBUG=1      Build a debug build (assertions, no opt)
#

CC := ../out/llvmbox/bin/clang
CFLAGS ?=
LDFLAGS ?=
TARGET_SYS ?= $(shell uname -s)
TARGET_ARCH ?= $(shell uname -m)
DESTDIR ?= ../out/llvmbox-tools
BINDIR ?= $(DESTDIR)/bin
OBJDIR := .obj
SRCROOT := $(shell pwd)
Q := $(if $(filter 1,$(V) $(VERBOSE)),,@)

CFLAGS += -g -std=c11 -MMD \
	-ffile-prefix-map=$(SRCROOT)/= \
  -feliminate-unused-debug-types \
  -fvisibility=hidden \
  -Wall -Wextra -Wvla -Wimplicit-fallthrough -Wno-missing-field-initializers \
  -Wno-unused-parameter -Werror=implicit-function-declaration \
  -Werror=incompatible-pointer-types -Werror=int-conversion -Werror=format \
  -Wcovered-switch-default -Werror=format-insufficient-args \
  -Werror=bitfield-constant-conversion -Wno-pragma-once-outside-header \
  -DLLVM_VERSION=$(LLVM_VERSION) -DLLVMBOX_VERSION=$(LLVMBOX_VERSION)

ifeq ($(TARGET_SYS),Linux)
	CFLAGS += -fno-stack-protector # must disable ssp for musl static
	LDFLAGS += -static
# else ifeq ($(TARGET_SYS),Darwin)
endif

ifneq ($(DEBUG),)
	CFLAGS += -DDEBUG
	OBJDIR := .obj-debug
else
	CFLAGS += -O2 -DNDEBUG
	LDFLAGS += -dead_strip
endif

all_objs := \
	$(OBJDIR)/llvmboxlib.c.o \
	$(OBJDIR)/llvmbox-mksysroot.c.o \
	$(OBJDIR)/llvmbox-dedup-target-files.c.o

all: llvmbox-mksysroot llvmbox-cpmerge llvmbox-config llvmbox-dedup-target-files

llvmbox-mksysroot: $(OBJDIR)/llvmboxlib.c.o $(OBJDIR)/llvmbox-mksysroot.c.o
	@echo "link $@"
	$(Q)$(CC) $(LDFLAGS) $^ -o $@

llvmbox-cpmerge: $(OBJDIR)/llvmboxlib.c.o $(OBJDIR)/llvmbox-cpmerge.c.o
	@echo "link $@"
	$(Q)$(CC) $(LDFLAGS) $^ -o $@

llvmbox-config: $(OBJDIR)/llvmboxlib.c.o $(OBJDIR)/llvmbox-config.c.o
	@echo "link $@"
	$(Q)$(CC) $(LDFLAGS) $^ -o $@

llvmbox-dedup-target-files: $(OBJDIR)/llvmboxlib.c.o $(OBJDIR)/llvmbox-dedup-target-files.c.o
	@echo "link $@"
	$(Q)$(CC) $(LDFLAGS) $^ -o $@

install: | $(BINDIR)
	$(Q)cp $(EXE) $(BINDIR)/

$(OBJDIR)/%.c.o: %.c | $(OBJDIR)
	@echo "compile $<"
	$(Q)$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR):
	$(Q)mkdir -p $@

$(BINDIR):
	$(Q)mkdir -p $@

DEPS := ${all_objs:.o=.d}
-include $(DEPS)

clean:
	rm -f *.o $(EXE)
