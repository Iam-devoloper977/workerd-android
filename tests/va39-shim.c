#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

// Emulate 39-bit VA space (Android kernel limit) by blocking allocations from 2^39 to 2^48
static char buf[1 << 20];
static uintptr_t starts[4096], ends[4096];

static uintptr_t hex(const char **p) {
  uintptr_t v = 0;
  for (;; (*p)++) {
    char c = **p;
    if (c >= '0' && c <= '9') v = v * 16 + (c - '0');
    else if (c >= 'a' && c <= 'f') v = v * 16 + (c - 'a' + 10);
    else return v;
  }
}

static void reserve(uintptr_t a, uintptr_t b) {
  if (b > a) {
    mmap((void *)a, b - a, PROT_NONE,
         MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0);
  }
}

__attribute__((constructor(101))) static void va39_init(void) {
  const uintptr_t lo = (uintptr_t)1 << 39;
  const uintptr_t hi = (uintptr_t)1 << 48;
  int fd = open("/proc/self/maps", O_RDONLY);
  if (fd < 0) return;
  ssize_t n = 0, r;
  while (n < (ssize_t)sizeof(buf) - 1 && (r = read(fd, buf + n, sizeof(buf) - 1 - n)) > 0) {
    n += r;
  }
  close(fd);
  buf[n] = 0;

  int cnt = 0;
  for (const char *p = buf; *p && cnt < 4096;) {
    uintptr_t s = hex(&p);
    p++;
    uintptr_t e = hex(&p);
    starts[cnt] = s;
    ends[cnt] = e;
    cnt++;
    while (*p && *p != '\n') p++;
    if (*p) p++;
  }

  uintptr_t cur = lo;
  for (int i = 0; i < cnt; i++) {
    if (ends[i] <= cur) continue;
    if (starts[i] >= hi) break;
    reserve(cur, starts[i] < hi ? starts[i] : hi);
    cur = ends[i];
  }
  reserve(cur, hi);
}
