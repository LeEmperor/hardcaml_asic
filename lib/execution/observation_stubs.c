#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/unixsupport.h>

/* Borrowed descriptor: ownership/release belongs to the OCaml writer. */
CAMLprim value hardcaml_asic_observation_lock(value fd) {
  if (flock(Int_val(fd), LOCK_EX | LOCK_NB) < 0) uerror("flock", Nothing);
  return Val_unit;
}

/* flock, not lockf: interoperates with the existing Python writer. Never creates
   or writes a lock file. Closing the fresh descriptor releases a successful probe. */
CAMLprim value hardcaml_asic_observation_active(value path) {
  int fd = open(String_val(path), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return Val_int(-1);
  int result = flock(fd, LOCK_EX | LOCK_NB);
  int saved = errno;
  close(fd);
  return Val_int(result == 0 ? 0 :
                 (saved == EWOULDBLOCK || saved == EAGAIN) ? 1 : -1);
}

/* Unix.stat float times lose low nanoseconds. Preserve exact Linux metadata. */
CAMLprim value hardcaml_asic_observation_metadata(value path) {
  struct stat s;
  if (lstat(String_val(path), &s) < 0) uerror("lstat", path);
  if (!S_ISREG(s.st_mode)) {
    errno = EINVAL;
    uerror("record must be a regular non-symlink file", path);
  }
  char buf[256];
  snprintf(buf, sizeof(buf), "%ju:%ju:%jd:%jd:%ld:%jd:%ld",
           (uintmax_t)s.st_dev, (uintmax_t)s.st_ino, (intmax_t)s.st_size,
           (intmax_t)s.st_mtim.tv_sec, s.st_mtim.tv_nsec,
           (intmax_t)s.st_ctim.tv_sec, s.st_ctim.tv_nsec);
  return caml_copy_string(buf);
}
