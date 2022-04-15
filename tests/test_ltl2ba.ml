open Parsing
open Ltl
open Core
open Algorithm
open Test_utils
module Al = Alcotest

module To_test = struct
  let nnf (formula : string) : formula option =
    let lexbuf = Lexing.from_string formula in
    try
      let phi = Parser.formula Lexer.read lexbuf in
      Some (Ltl.nnf phi)
    with
    | Lexer.Syntax_error _msg -> None
    | Parser.Error -> None
  ;;

  let next : state -> state = Algorithm.next
  let is_reduced : state -> bool = Algorithm.is_reduced
  let is_maximal : formula -> state -> bool = Algorithm.is_maximal
  let red : state -> state = Algorithm.red
end

let al_assert_formula_eq = al_assert_formula_eq_according_to_test To_test.nnf

(* Test cases *)

let test_nnf_false () = al_assert_formula_eq "false" Ltl.(Bool false)
let test_nnf_next () = al_assert_formula_eq "X(p)" Ltl.(next (Prop "p"))
let test_nnf_neg_p () = al_assert_formula_eq "!p" Ltl.(neg (Prop "p"))
let test_nnf_neg_neg_p () = al_assert_formula_eq "!!p" Ltl.(Prop "p")
let test_nnf_neg_next () = al_assert_formula_eq "!X(p)" Ltl.(next @@ neg @@ Prop "p")

let test_nnf_neg_or () =
  al_assert_formula_eq "!(p | q)" Ltl.(neg (Prop "p") <&> neg (Prop "q"))
;;

let test_nnf_neg_and () =
  al_assert_formula_eq "!(p & q)" Ltl.(neg (Prop "p") <|> neg (Prop "q"))
;;

let test_nnf_neg_until () =
  al_assert_formula_eq "!(p U q)" Ltl.(neg (Prop "p") <^> neg (Prop "q"))
;;

let test_nnf_neg_release () =
  al_assert_formula_eq "!(p R q)" Ltl.(neg (Prop "p") <~> neg (Prop "q"))
;;

let test_nnf_real1 () =
  al_assert_formula_eq
    "!(!(p U q) R (X p))"
    Ltl.(Prop "p" <~> Prop "q" <~> next (neg (Prop "p")))
;;

let test_nnf_example1 () =
  al_assert_formula_eq "p U Xq" Ltl.(Prop "p" <~> next (Prop "q"))
;;

let test_nnf_example2 () =
  al_assert_formula_eq
    "G(p => XFq)"
    Ltl.(Bool false <^> (neg (Prop "p") <|> next (Bool true <~> Prop "q")))
;;

let test_next_next_p () =
  let next_z = FormulaSet.singleton Ltl.(next (Prop "p"))
  and z = FormulaSet.singleton (Ltl.Prop "p") in
  al_assert "should be equals" (FormulaSet.equal (To_test.next next_z) z)
;;

let test_next_p () =
  let z = FormulaSet.singleton Ltl.(Prop "p") in
  al_assert "should be equals" FormulaSet.(equal (To_test.next z) empty)
;;

let test_next_multiple_formulas () =
  let next_z =
    FormulaSet.of_list Ltl.[ next (Prop "p"); next (next (Prop "q")); Bool false ]
  and z = FormulaSet.of_list Ltl.[ Prop "p"; next (Prop "q") ] in
  al_assert "should be equals" (FormulaSet.equal (To_test.next next_z) z)
;;

let test_next_empty_set () =
  al_assert "should be equals" FormulaSet.(equal (To_test.next empty) empty)
;;

let test_is_reduced_empty () =
  al_assert "should be reduced" (To_test.is_reduced FormulaSet.empty)
;;

let test_is_reduced_false () =
  al_assert
    "should not be reduced"
    (not @@ To_test.is_reduced (FormulaSet.singleton Ltl.(Bool false)))
;;

let test_is_reduced_true () =
  al_assert
    "should be reduced"
    (To_test.is_reduced (FormulaSet.singleton Ltl.(Bool true)))
;;

let test_is_reduced_p () =
  al_assert "should be reduced" (To_test.is_reduced (FormulaSet.singleton Ltl.(Prop "p")))
;;

let test_is_reduced_p_and_not_p () =
  let p = Ltl.Prop "p" in
  let not_p = Ltl.neg p in
  al_assert
    "should not be reduced"
    (not @@ To_test.is_reduced (FormulaSet.of_list [ p; not_p ]))
;;

let test_is_reduced_p_and_not_q () =
  let p = Ltl.Prop "p" in
  let not_q = Ltl.(neg (Prop "q")) in
  al_assert "should be reduced" (To_test.is_reduced (FormulaSet.of_list [ p; not_q ]))
;;

let test_is_reduced_p_and_not_q_and_next_p () =
  let p = Ltl.Prop "p" in
  let not_q = Ltl.(neg (Prop "q")) in
  let next_p = Ltl.next p in
  al_assert
    "should be reduced"
    (To_test.is_reduced (FormulaSet.of_list [ p; not_q; next_p ]))
;;

let test_is_reduced_p_and_complex_formula () =
  let p = Ltl.Prop "p" in
  let p_U_Xq = Ltl.(Prop "p" <~> next (Prop "q")) in
  al_assert
    "should not be reduced"
    (not @@ To_test.is_reduced (FormulaSet.of_list [ p; p_U_Xq ]))
;;

let test_red_empty () =
  al_assert "should be empty" FormulaSet.(empty = To_test.red FormulaSet.empty)
;;

let test_is_maximal_phi_not_in_state () =
  al_assert "should be false" (not @@ To_test.is_maximal (Bool true) FormulaSet.empty)
;;

let test_is_maximal_p_in_p () =
  let p = Prop "p" in
  al_assert "should be true" (To_test.is_maximal p (FormulaSet.singleton p))
;;

let test_is_not_maximal () =
  let p = Prop "p"
  and q = Prop "q" in
  let state = FormulaSet.of_list [ p; q; q <~> (p <^> q) ] in
  al_assert "should not be true" (not @@ To_test.is_maximal p state)
;;

let () =
  Al.run
    "LTL to Büchi automata"
    Al.
      [ ( "Negation normal form"
        , [ test_case "nnf(⊥) = ⊥" `Quick test_nnf_false
          ; test_case "nnf(Xp) = Xp" `Quick test_nnf_next
          ; test_case "nnf(¬p) = ¬p" `Quick test_nnf_neg_p
          ; test_case "nnf(¬¬p) = p" `Quick test_nnf_neg_neg_p
          ; test_case "nnf(¬Xp) = X¬p" `Quick test_nnf_neg_next
          ; test_case "nnf(¬(p ∨ q)) = ¬p ∧ ¬q" `Quick test_nnf_neg_or
          ; test_case "nnf(¬(p ∧ q)) = ¬p v ¬q" `Quick test_nnf_neg_and
          ; test_case "nnf(¬(p U q)) = ¬p R ¬q" `Quick test_nnf_neg_until
          ; test_case "nnf(¬(p R q)) = ¬p U ¬q" `Quick test_nnf_neg_release
          ; test_case "nnf(p U Xq) = p U Xq" `Quick test_nnf_example1
          ; test_case "nnf(G(¬p ∨ XFq) = ?" `Quick test_nnf_example2
          ; test_case "nnf(¬(¬(p U q) R (X p))) = (p U q) U (X ¬p))" `Quick test_nnf_real1
          ] )
      ; ( "Next"
        , [ test_case "next({Xp}) = {p}" `Quick test_next_next_p
          ; test_case "next({p}) = {}" `Quick test_next_p
          ; test_case "next({Xp, XXq, ⊥}) = {p, Xq}" `Quick test_next_multiple_formulas
          ; test_case "next({}) = {}" `Quick test_next_empty_set
          ] )
      ; ( "State is reduced"
        , [ test_case "is_reduced({})" `Quick test_is_reduced_empty
          ; test_case "is_reduced({⊤})" `Quick test_is_reduced_true
          ; test_case "is_reduced({p})" `Quick test_is_reduced_p
          ; test_case "is_reduced({p, ¬q})" `Quick test_is_reduced_p_and_not_q
          ; test_case
              "is_reduced({p, ¬q, Xp}) "
              `Quick
              test_is_reduced_p_and_not_q_and_next_p
          ; test_case "not is_reduced({p, ¬p})" `Quick test_is_reduced_p_and_not_p
          ; test_case "not is_reduced({⊥})" `Quick test_is_reduced_false
          ; test_case
              "not is_reduced({p, (p U Xq)})"
              `Quick
              test_is_reduced_p_and_complex_formula
          ] )
      ; ( "Formula is maximal in state"
        , [ test_case "not is_maximal(⊤, {})" `Quick test_is_maximal_phi_not_in_state
          ; test_case "is_maximal(p, {p})" `Quick test_is_maximal_p_in_p
          ; test_case "not is_maximal(p, {p, q, q U (p R q)})" `Quick test_is_not_maximal
          ] )
      ; ( "Calculate Red(Z)"
        , [ test_case "Red({}) = {}" `Quick test_red_empty
          ; test_case "Red({p, ¬q, Xp}) = {p, ¬q, Xp}" `Quick test_red_empty
          ] )
      ]
;;