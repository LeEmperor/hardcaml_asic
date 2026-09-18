(lang dune 3.17)

(name hardcaml_asic)
(version 0.1.0)

(generate_opam_files true)

(source
 (github LeEmperor/hardcaml_asic))

(authors "Bohdan Purtell <bohdanpurtell@gmail.com>")
(maintainers "Bohdan Purtell <bohdanpurtell@gmail.com>")

(package
 (name hardcaml_asic)
 (synopsis "Hardcaml ASIC project and Tiny Tapeout bundle library")
 (description "Project elaboration, registered resources, and TT/LibreLane bundle emission")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.17))
  core
  hardcaml
  yojson
  cryptokit
  ppx_jane
  (ppx_hardcaml :with-test)
  (expect_test_helpers_core :with-test)))
