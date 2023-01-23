/*
MIT License

Copyright (c) 2020 Jakub Konka <kubkon@jakubkonka.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// Source: https://en.wikipedia.org/wiki/C_standard_library#Header_files
#include <assert.h>
#include <complex.h>
#include <ctype.h>
#include <errno.h>
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <iso646.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdalign.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdnoreturn.h>
#include <string.h>
#include <tgmath.h>
#include <time.h>
#include <wchar.h>
#include <wctype.h>

// Source: https://en.wikipedia.org/wiki/C_POSIX_library
#include <aio.h>
#include <arpa/inet.h>
#include <assert.h>
#include <complex.h>
#include <cpio.h>
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <fenv.h>
#include <float.h>
#include <fmtmsg.h>
#include <fnmatch.h>
#include <ftw.h>
#include <glob.h>
#include <grp.h>
#include <iconv.h>
#include <inttypes.h>
#include <iso646.h>
#include <langinfo.h>
#include <libgen.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <monetary.h>
/* #include <mqueue.h> - not found on macos catalina */
#include <ndbm.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <nl_types.h>
#include <poll.h>
#include <pthread.h>
#include <pwd.h>
#include <regex.h>
#include <sched.h>
#include <search.h>
#include <semaphore.h>
#include <setjmp.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
/* #include <stropts.h> - not found on macos catalina */
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/msg.h>
#include <sys/random.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <syslog.h>
#include <tar.h>
#include <termios.h>
#include <tgmath.h>
#include <time.h>
/* #include <trace.h> - not found on macos catalina */
#include <ulimit.h>
#include <unistd.h>
#include <utime.h>
#include <utmpx.h>
#include <wchar.h>
#include <wctype.h>
#include <wordexp.h>

// macOS system headers
#include <mach/clock.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_state.h>
#include <mach/vm_param.h>
#include <sys/acl.h>
#include <sys/attr.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/clonefile.h>
#include <libproc.h>

// Depended on by libcxx
#include <Block.h>
#include <xlocale.h>
#include <copyfile.h>
#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/arch.h>
#include <mach-o/stab.h>
#include <mach-o/ranlib.h>
#include <mach-o/compact_unwind_encoding.h>
#include <mach-o/arm64/reloc.h>
#include <mach-o/x86_64/reloc.h>
#include <ar.h>

// Depended on by LLVM
#include <sysexits.h>
#include <crt_externs.h>
#include <execinfo.h>

// Depended on by several frameworks
#include <AssertMacros.h>
#include <device/device_types.h>
#include <dispatch/dispatch.h>
#include <hfs/hfs_format.h>
#include <hfs/hfs_unistr.h>
#include <libkern/OSAtomic.h>
#include <libkern/OSTypes.h>
#include <MacTypes.h>
#include <os/lock.h>
#include <simd/simd.h>
#include <xpc/xpc.h>
#include <CommonCrypto/CommonDigest.h>

#include <objc/message.h>
#include <objc/NSObject.h>
#include <objc/NSObjCRuntime.h>
#include <objc/objc.h>
#include <objc/objc-runtime.h>

// Depended on by libuv
#include <ifaddrs.h>
#include <net/if_dl.h>

// Depended on by sqlite-amalgamation
#include <sys/file.h>
#include <malloc/malloc.h>

// Provided by macOS LibC
#include <memory.h>

#define _XOPEN_SOURCE
#include <ucontext.h>

int main(int argc, char **argv) {
    return 0;
}
