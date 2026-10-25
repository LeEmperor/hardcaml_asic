let operation_limit = 4 * 1024 * 1024
let snapshot_limit = 64 * 1024 * 1024
let read_bytes_with ~after_lstat ~limit path =
  if limit<=0 then invalid_arg "invalid preparation evidence size limit";
  let regular (st:Unix.LargeFile.stats) =
    if st.st_kind<>Unix.S_REG then invalid_arg ("preparation evidence must be a regular non-symlink file: "^path);
    if st.st_size>Int64.of_int limit then invalid_arg ("preparation evidence exceeds size limit: "^path) in
  let before=Unix.LargeFile.lstat path in
  regular before;
  after_lstat ();
  (* O_NONBLOCK is essential even after lstat: the leaf could have been replaced
     with a FIFO between the type check and open. fstat precedes every read. *)
  let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun ()->Unix.close fd) (fun ()->
    let opened=Unix.LargeFile.fstat fd in
    regular opened;
    let same a b = a.Unix.LargeFile.st_dev=b.Unix.LargeFile.st_dev && a.st_ino=b.st_ino in
    if not (same before opened) then invalid_arg "preparation evidence changed during open";
    let buffer=Buffer.create (min limit 65536) and chunk=Bytes.create 65536 in
    let rec loop total =
      let n=Unix.read fd chunk 0 (min (Bytes.length chunk) (limit-total+1)) in
      if n>0 then (
        if n>limit-total then invalid_arg ("preparation evidence exceeds size limit: "^path);
        Buffer.add_subbytes buffer chunk 0 n;loop (total+n)) in
    loop 0;
    let after=Unix.LargeFile.fstat fd and leaf=Unix.LargeFile.lstat path in
    regular after;regular leaf;
    if not (same opened leaf) || opened.st_size<>after.st_size ||
       opened.st_mtime<>after.st_mtime || opened.st_ctime<>after.st_ctime then
      invalid_arg "preparation evidence changed during read";
    Buffer.contents buffer)
let read_bytes = read_bytes_with ~after_lstat:(fun ()->())
module For_testing = struct let read_bytes = read_bytes_with end
