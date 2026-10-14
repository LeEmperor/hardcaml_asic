(** Scoped Python checkpoint/journal identity JSON, not RFC 8785.

    Canonical bytes match [json.dumps(sort_keys=True, separators=(",", ":"),
    ensure_ascii=True, allow_nan=False)] on the supported domain. Integers have
    arbitrary decimal precision (Python's configurable integer digit-count
    resource limit is not reproduced). Strings are UTF-8 Unicode scalars (unpaired
    surrogates are unsupported). Object keys are unique and sorted by Unicode
    code point, without normalization.

    All finite binary64 floats are supported, including subnormals and extremal
    values. Exact rounding-interval arithmetic selects the shortest decimal,
    nearest to the value with ties to even, then applies Python's notation
    thresholds and exponent spelling. Signed zero and the integer/float
    distinction are preserved. Decimal float tokens round to binary64; overflow
    is rejected and underflow preserves the sign of zero. No hash-time rounding
    or numeric type coercion is performed.

    No schema validation, file publication, or backend state decoding is implied.
    In particular LibreLane state with Infinity is outside this codec. *)
type t = private
  | Null
  | Bool of bool
  | String of string
  | Integer of string
  | Float of float
  | Array of t list
  | Object of (string * t) list

type error =
  | Malformed of string
  | Duplicate_key of string
  | Invalid_unicode
  | Nonfinite
  (** Retained for source compatibility; no finite binary64 value produces it. *)
  | Unsupported_float

val error_message : error -> string
val null : t
val bool : bool -> t
val string : string -> (t, error) result
val integer : string -> (t, error) result
val float : float -> (t, error) result
val array : t list -> t
val object_ : (string * t) list -> (t, error) result

(** Strict JSON grammar, including nested duplicate-key detection, no trailing
    data, no NaN/Infinity or exponent overflow. Maximum nesting depth is 256.
    Unsupported but valid JSON is distinguished from malformed input. *)
val parse : string -> (t, error) result

(** Compact ASCII bytes, without a trailing newline. *)
val canonical : t -> string
val sha256_bytes : string -> string
val identity : t -> string

(** Require exactly the named fields; rejects nonobjects, missing/extra fields,
    and duplicate names in the expected field specification. *)
val exact_object : t -> fields:string list -> ((string * t) list, error) result

(** Remove an existing signature field before hashing; fails if absent or if
    the value is not an object. Useful for [identity] and [sha256] envelopes. *)
val unsigned : t -> field:string -> (t, error) result
