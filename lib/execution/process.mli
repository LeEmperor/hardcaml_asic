(** Explicit POSIX launch specification. No shell or PATH search. *)
type output = File of string | Descriptor of Unix.file_descr
type t = private
  { prog : string
  ; argv : string list
  ; cwd : string
  ; environment : string list
  ; stdout : output
  ; stderr : output
  }

val make
  :  prog:string
  -> argv:string list
  -> cwd:string
  -> environment:string list
  -> stdout:output
  -> stderr:output
  -> t
(** Requires absolute executable, cwd and output paths, nonempty argv, no NULs,
    and unique KEY=VALUE environment entries. Raises [Invalid_argument].
    File outputs are created exclusively (0600); identical stdout/stderr paths
    share one descriptor and form a merged log. Supplied descriptors are borrowed,
    never closed; use regular files, not undrained pipes. Stdin is /dev/null.
    The environment is the complete child environment, not an overlay. *)
