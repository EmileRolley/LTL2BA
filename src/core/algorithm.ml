open Ltl
open Automata

type red_states =
  { all : StateSet.t
  ; marked_by : StateSet.t FormulaMap.t
  }

let empty_red_states = { all = StateSet.empty; marked_by = FormulaMap.empty }

let states_to_string states =
  StateSet.fold
    (fun f s ->
      s
      ^ (if 0 <> String.length s then ", " else "")
      ^ state_to_string ~surround:`Braces f)
    states
    ""
;;

(* TODO: could factorized with [state_to_string]. *)
let red_states_to_string (states : red_states) : string =
  Printf.sprintf
    "red_states = {\n\t  all: { %s };\n\t  marked_by: { %s }\n\t}"
    (states_to_string states.all)
    (FormulaMap.fold
       (fun f states str ->
         str
         ^ (if 0 <> String.length str then ", " else "")
         ^ "<"
         ^ Ltl.to_string f
         ^ "> = "
         ^ states_to_string states)
       states.marked_by
       "")
;;

let next state =
  FormulaSet.filter_map
    (function
      | Uop (Next, phi) -> Some phi
      | _ -> None)
    state
;;

let sigma state =
  FormulaSet.(
    fold
      (fun phi formula_set ->
        match phi with
        | Prop _ | Uop (Not, Prop _) -> add phi formula_set
        | _ -> formula_set)
      state
      empty)
;;

let formula_is_reduced = function
  | Bool b ->
    (* ⊥ ∉ Z *)
    b
  | Prop _ | Uop (Not, Prop _) | Uop (Next, _) ->
    (* formulas of Z are of the form: p, ¬q, or Xα *)
    true
  | _ -> false
;;

let is_reduced state =
  state
  |> FormulaSet.for_all (function
         | Bool b ->
           (* ⊥ ∉ Z *)
           b
         | Prop p ->
           (* ∀.p ∈ AP, \{p, ¬p\} ⊈ Z *)
           FormulaSet.for_all
             (function
               | Uop (Not, Prop q) -> p <> q
               | _ -> true)
             state
         | Uop (Not, Prop _) | Uop (Next, _) ->
           (* formulas of Z are of the form: p, ¬q, or Xα *)
           true
         | _ -> false)
;;

let is_maximal phi state =
  let open FormulaSet in
  if not (mem phi state)
  then false
  else (
    let s = remove phi state in
    is_empty s || (not @@ exists (fun psi -> Ltl.(is_subformula psi phi)) s))
;;

let red state =
  let open StateSet in
  (* Reduces first maximal not reduced subset of [tmp_state] *)
  let reduce_state (tmp_state : state) : red_states =
    Printf.printf "\tReducing state: %s\n" (state_to_string tmp_state);
    (* Finds first maximal not reduced subset of [tmp_state], if exists, otherwise,
       returns simply the first formula of [tmp_state]. *)
    let unreduced_subset =
      tmp_state |> FormulaSet.filter (fun phi -> not (formula_is_reduced phi))
    in
    let alpha =
      unreduced_subset
      |> FormulaSet.filter (fun phi -> is_maximal phi unreduced_subset)
      |> FormulaSet.choose
    in
    Printf.printf "\tMaximal unreduced formula: %s\n" (to_string alpha);
    let tmp_state = FormulaSet.remove alpha tmp_state in
    match alpha with
    | Bop (a1, Or, a2) ->
      (* If α = α1 ∨ α2, Y ⟶ Z ∪ {α1} and Y ⟶ Z ∪ {α2} *)
      { all =
          empty |> add FormulaSet.(add a1 tmp_state) |> add FormulaSet.(add a2 tmp_state)
      ; marked_by = FormulaMap.empty
      }
    | Bop (a1, And, a2) ->
      (* If α = α1 ∧ α2, Y ⟶ Z ∪ {α1, α2} *)
      { all = empty |> add FormulaSet.(tmp_state |> add a1 |> add a2)
      ; marked_by = FormulaMap.empty
      }
    | Bop (a1, Release, a2) ->
      (* If α = α1 R α2, Y ⟶ Z ∪ {α1, α2} and Y ⟶ Z ∪ {Xα, α2} *)
      { all =
          empty
          |> add FormulaSet.(tmp_state |> add a1 |> add a2)
          |> add FormulaSet.(tmp_state |> add (Ltl.next alpha) |> add a2)
      ; marked_by = FormulaMap.empty
      }
    | Bop (a1, Until, a2) ->
      (* If α = α1 U α2, Y ⟶ Z ∪ {α2} and Y ⟶α Z ∪ {Xα, α1} *)
      let second_set = FormulaSet.(tmp_state |> add (Ltl.next alpha) |> add a1) in
      { all = empty |> add FormulaSet.(add a2 tmp_state) |> add second_set
      ; marked_by = FormulaMap.singleton alpha (singleton second_set)
      }
    | _ ->
      failwith
        " should never be reached, as [alpha] is the maximal not reduced subset of [state]\n"
  in
  let remove_dead_states : StateSet.t -> StateSet.t =
    let contains_phi_and_not_phi state : bool =
      FormulaSet.exists (fun phi -> FormulaSet.mem (neg phi) state) state
    in
    StateSet.filter (fun state ->
        not (FormulaSet.mem (Bool false) state || contains_phi_and_not_phi state))
  in
  (* Reduces the state in [states] until all states are reduced, meaning that [states]
     contains all the leafs of the temporary oriented graph built from [state] *)
  let rec reduce (red_states : red_states) : red_states =
    if for_all is_reduced red_states.all
    then red_states
    else (
      let new_states =
        red_states.all
        |> remove_dead_states
        |> fun states_without_false ->
        StateSet.fold
          (fun state new_states ->
            if is_reduced state
            then { new_states with all = add state new_states.all }
            else reduce_state state)
          states_without_false
          empty_red_states
      in
      (* FIXME: both reducing should be done in the same time -> issue when multiple
         reducing in a row. *)
      let new_states =
        FormulaMap.fold
          (fun phi states new_states ->
            states
            |> remove_dead_states
            |> fun states_without_false ->
            StateSet.fold
              (fun state new_states ->
                if is_reduced state
                then
                  { new_states with
                    marked_by =
                      FormulaMap.add phi (StateSet.singleton state) new_states.marked_by
                  }
                else reduce_state state)
              states_without_false
              new_states)
          red_states.marked_by
          new_states
      in
      reduce new_states)
  in
  if FormulaSet.is_empty state
  then empty_red_states
  else reduce { all = singleton state; marked_by = FormulaMap.empty }
;;
