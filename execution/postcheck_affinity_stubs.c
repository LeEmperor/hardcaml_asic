#define _GNU_SOURCE
#include <sched.h>
#include <errno.h>
#include <string.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

/* Children inherit this mask; restoration cannot expand spawned groups. */
CAMLprim value hardcaml_postcheck_affinity_enter(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(saved);
  cpu_set_t old, limited;
  if (sched_getaffinity(0, sizeof(old), &old)) caml_failwith(strerror(errno));
  CPU_ZERO(&limited);
  int n = 0;
  for (int i = 0; i < CPU_SETSIZE && n < 20; i++)
    if (CPU_ISSET(i, &old)) { CPU_SET(i, &limited); n++; }
  saved = caml_alloc_string(sizeof(old));
  memcpy(Bytes_val(saved), &old, sizeof(old));
  if (sched_setaffinity(0, sizeof(limited), &limited)) caml_failwith(strerror(errno));
  CAMLreturn(saved);
}
CAMLprim value hardcaml_postcheck_affinity_leave(value saved) {
  CAMLparam1(saved);
  cpu_set_t old;
  if (caml_string_length(saved) != sizeof(old)) caml_invalid_argument("affinity mask");
  memcpy(&old, String_val(saved), sizeof(old));
  if (sched_setaffinity(0, sizeof(old), &old)) caml_failwith(strerror(errno));
  CAMLreturn(Val_unit);
}
