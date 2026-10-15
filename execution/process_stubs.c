#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/unixsupport.h>

CAMLprim value hardcaml_asic_monotonic(value unit) {
  struct timespec t;
  if (clock_gettime(CLOCK_MONOTONIC, &t) < 0) uerror("clock_gettime", Nothing);
  return caml_copy_double((double)t.tv_sec + (double)t.tv_nsec / 1e9);
}

/* WNOWAIT pins the leader PID until group cleanup has finished. */
CAMLprim value hardcaml_asic_child_exited(value pid) {
  siginfo_t info = {0};
  int r;
  do { r = waitid(P_PID, Int_val(pid), &info, WEXITED | WNOHANG | WNOWAIT); }
  while (r < 0 && errno == EINTR);
  if (r < 0) uerror("waitid", Nothing);
  return Val_bool(info.si_pid != 0);
}

/* No exists/rename race, even when another publisher creates an empty dir. */
CAMLprim value hardcaml_asic_rename_noreplace(value source, value dest) {
  if (renameat2(AT_FDCWD, String_val(source), AT_FDCWD, String_val(dest),
                RENAME_NOREPLACE) < 0)
    uerror("renameat2(RENAME_NOREPLACE)", dest);
  return Val_unit;
}
