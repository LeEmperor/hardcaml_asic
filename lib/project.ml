(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "project.ml" *)
(* Behaviour of the actual project system; promises derived from project.mli
*)

open! Core
open! Hardcaml

[@@@ocamlformat "disable"]
(* Design items of the signature from the MLI *)
module type Design = sig
  module I : Interface.S
  module O : Interface.S

  val name : string
  val create :
    Elaboration_context.t ->
    Signal.t I.t ->
    Signal.t O.t
end

type t =
  { name      : string
  ; metadata  : Metadata.t
  ; design    : (module Design)
  ; target    : Target.t
  ; flow      : Flow.t
  ; clocks    : Clock.t list
  ; policy    : Resource_policy.t
  }

let create
    ~name
    ~metadata
    ~design
    ~target
    ~flow
    ?(clocks = [])
    ~policy ()
  =
  (* Glorified validation function on all of the inputs;

    Checks each input is valid in it's construction and use,
      If valid -> returns the record out to the caller
      If not valid -> returns all errors of whatever items are incorrect

    This is a fun ppx sugar for Or_error.map

    Or_error.t is the Jane result type; declare "Ok x or Error.t" in layman's terms. More to it but not that we care about right here.

    TODO: Validate target and policy; currently staved for later.
  *)
  let%map.Or_error () =
    (* Or_err -> checks for error returns on all members; this doesn't short circuit like a more naive item might; *)
    Or_error.combine_errors_unit

      [ (if Resource_id.is_valid_component name (* project name must be literal identifier *)
         then Ok ()
         else
           Or_error.error_s
             [%message "project name must be an identifier" (name : string)])

      ; Metadata. validate      metadata  (* nonblank title *)
      ; Clock.    validate_list clocks    (* ports nonempty, periods > 0, no dups *)
      ; Flow.     validate      flow      (* librelane overrides formed correctly *)
      ]

    (* if there was an error, tag it with where the error belongs in the project scheme *)
    |> Or_error.tag_s ~tag:[%message "invalid project declaration" (name : string)]
  in

  (* Nice return record if all OK; otherwise an error group gets formed; *)
  { name
  ; metadata
  ; design
  ; target
  ; flow
  ; clocks
  ; policy
  }
;;

let name t = t.name

(* Runs the user's design once, and returns the Build.t object *)
let elaborate t ~mode =
  (* Unpack our first class design module *)
  let (module D) = t.design in

  (* Functor on I and O to make the Circuit.t out of create_exn calls *)
  let module C = Circuit.With_interface (D.I) (D.O) in

  (* Represent error handling with the expanded context under an error happening; *)
  let tag message =
    Or_error.tag_s ~tag:[%message message ~project:t.name (mode : Elaboration_mode.t)]
  in

  (* Overall Circuit.t scope *)
  let scope = Scope.create ~flatten_design:true () in

  (* Context creation; This is only lived as long as a given elaboration run, and that is the
  intention behind a context; think of it perhaps as a temporary database for things with an elaboration run to exist within and communicate via;

     Contexts hold their mode, technology theyre implementing on, a resource policy, and a scope.
  *)
  let context =
    Elaboration_context.Private.create
      ~mode
      ~technology:t.target.technology
      ~policy:t.policy
      ~scope
  in

  (* Runs the user's design and catches any of the errors that are emitted out; *)
  match Or_error.try_with ( (* Any exception is turned into an error instead, and registered. *)
    (* Passes a partial context in order to create the Signal.t I -> Signal.t O that create_exn wants to make the Circuit.t *)
    fun () -> C.create_exn ~name:D.name (D.create context)
  ) with

  (* Context error plug *)
  | Error _ as error ->
    Elaboration_context.Private.fail context;
    tag "design construction failed" error

  (* Ok circuit generation; validates on the resouces first; *)
  | Ok circuit ->
    let%map.Or_error resources =
      (* Good! -> Finalize; This closes the context and returns the resource records. *)
      Elaboration_context.Private.finalize context |> tag "elaboration validation failed"
    in

    (* Only runs if the above resources validate runs based on the context;
    Also adheres on a Private convention as this is a version valid to run a Project.Build.create call; *)
    Build.Private.create
      ~project_name:t.name
      ~metadata:t.metadata
      ~mode
      ~target:t.target
      ~flow:t.flow
      ~clocks:t.clocks
      ~resources
      ~circuit

  (* Note about Private:
      Technically OCaml doesn't really adhere to the public private thing, as these "Private" things can be accessed by others.
      This is a Jane convention to give some OOP (God be damned) to functional systems.

      For example, a Project.t is the only person that is *supposed* to make a Built.t and own an Context.t
      "Private" simply tells other people *you really shouldn't be touching this*.
  *)
;;
[@@@ocamlformat "enable"]
