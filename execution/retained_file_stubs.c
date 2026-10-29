#define _GNU_SOURCE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Component-by-component openat avoids a check-then-open symlink race. The leaf
 * is nonblocking even if a regular file was replaced by a FIFO before open. */
CAMLprim value hardcaml_asic_retained_open(value path)
{
  CAMLparam1(path);
  const char *original = String_val(path);
  char *copy = NULL, *cursor, *component;
  int directory = -1, result = -1, saved;
  if (strlen(original) != caml_string_length(path) || !*original) {
    errno = EINVAL; uerror("retained_open", path);
  }
  copy = strdup(original);
  if (!copy) { errno = ENOMEM; uerror("retained_open", path); }
  directory = open(original[0] == '/' ? "/" : ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (directory < 0) goto failed;
  cursor = copy;
  while ((component = strsep(&cursor, "/")) != NULL) {
    if (!*component || !strcmp(component, ".")) continue;
    if (!strcmp(component, "..")) { errno = EINVAL; goto failed; }
    while (cursor && *cursor == '/') cursor++;
    if (cursor && !*cursor) cursor = NULL;
    if (!cursor) {
      result = openat(directory, component, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
      if (result < 0) goto failed;
      close(directory); free(copy);
      CAMLreturn(Val_int(result));
    }
    result = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (result < 0) goto failed;
    close(directory); directory = result; result = -1;
  }
  errno = EINVAL;
failed:
  saved = errno;
  if (directory >= 0) close(directory);
  free(copy); errno = saved;
  uerror("retained_open", path);
  CAMLreturn(Val_int(-1));
}
