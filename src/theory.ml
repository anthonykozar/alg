(* Singatures, terms, equations and axioms. *)

(* Variables and operations are represented as integers, but we also keep around
   the original operation names so that results can be printed. *)
type operation = int
type relation = int
type operation_name = string
type relation_name = string

type variable = int

(* A term *)
type term =
  | Var of variable
  | Elem of int
  | Const of operation
  | Unary of operation * term
  | Binary of operation * term * term

(* An equation. *)
type equation' = term * term

type equation = int * equation'

(* A raw formula. *)
type formula' = 
  | True
  | False
  | Predicate of relation * term
  | Relation of relation * term * term
  | Equal of term * term
  | Forall of variable * formula'
  | Exists of variable * formula'
  | And of formula' * formula'
  | Or of formula' * formula'
  | Imply of formula' * formula'
  | Iff of formula' * formula'
  | Not of formula'

(* A formula in a context. The context is an array which is large enough for evaluation
   of the formula. *)
and formula = int array * formula'

(* A named property to be tested on each model *)
type propertytest = string * formula

type theory = {
  th_name : string;
  th_const : operation_name array;
  th_unary : operation_name array;
  th_binary : operation_name array;
  th_predicates : relation_name array;
  th_relations : relation_name array;
  th_equations : equation list;
  th_axioms : formula list;
  th_prop_tests : propertytest list
}

(* Used to indicate that a permanent inconsistency has been discovered. *)
exception InconsistentAxioms

(* Substitution functions. Warning: they assume no shadowing will occur. *)
let rec subst_term x t = function
  | Var y -> if x = y then t else Var y
  | Elem e -> Elem e
  | Const k -> Const k
  | Unary (f, s) -> Unary (f, subst_term x t s)
  | Binary (f, s1, s2) -> Binary (f, subst_term x t s1, subst_term x t s2)

let rec subst_formula x t = function
  | True -> True
  | False -> False
  | Predicate (p, s) -> Predicate (p, subst_term x t s)
  | Relation (r, s1, s2) -> Relation (r, subst_term x t s1, subst_term x t s2)
  | Equal (s1, s2) -> Equal (subst_term x t s1, subst_term x t s2)
  | Not f -> Not (subst_formula x t f)
  | And (f1, f2) -> And (subst_formula x t f1, subst_formula x t f2)
  | Or (f1, f2) -> Or (subst_formula x t f1, subst_formula x t f2)
  | Imply (f1, f2) -> Imply (subst_formula x t f1, subst_formula x t f2)
  | Iff (f1, f2) -> Iff (subst_formula x t f1, subst_formula x t f2)
  | Forall (y, f) -> Forall (y, subst_formula x t f)
  | Exists (y, f) -> Exists (y, subst_formula x t f)

(* Conversion to string, for debugging purposes. *)
let embrace s = "(" ^ s ^ ")"

let rec string_of_term = function
  | Var k -> "x" ^ string_of_int k
  | Elem e -> "e" ^ string_of_int e
  | Const k -> "c" ^ string_of_int k
  | Unary (f, t) -> "u" ^ string_of_int f ^ "(" ^ string_of_term t ^ ")"
  | Binary (f, t1, t2) -> "b" ^ string_of_int f ^ "(" ^ string_of_term t1 ^ ", " ^ string_of_term t2 ^ ")"

let string_of_equation (t1, t2) =
  string_of_term t1 ^ " = " ^ string_of_term t2

let rec string_of_formula' = function
  | True -> "True"
  | False -> "False"
  | Predicate (r, t) -> "p" ^ string_of_int r ^ " " ^ embrace (string_of_term t)
  | Relation (r, t1, t2) -> "r" ^ string_of_int r ^ " " ^ embrace (string_of_term t1 ^ ", " ^ string_of_term t2)
  | Equal (t1, t2) -> string_of_equation (t1, t2)
  | Not f -> "not " ^ embrace (string_of_formula' f)
  | And (f1, f2) -> embrace (string_of_formula' f1) ^ " /\\ " ^ embrace (string_of_formula' f2)
  | Or (f1, f2) -> embrace (string_of_formula' f1) ^ " \\/ " ^ embrace (string_of_formula' f2)
  | Imply (f1, f2) -> embrace (string_of_formula' f1) ^ " -> " ^ embrace (string_of_formula' f2)
  | Iff (f1, f2) -> embrace (string_of_formula' f1) ^ " <-> " ^ embrace (string_of_formula' f2)
  | Forall (x,f) -> "forall x" ^ string_of_int x ^ ", " ^ string_of_formula' f
  | Exists (x,f) -> "exists x" ^ string_of_int x ^ ", " ^ string_of_formula' f

let string_of_formula (a, f) = string_of_int (Array.length a) ^ " |- " ^ string_of_formula' f

let string_of_propertytest (nm, f) = nm ^ ": " ^ (string_of_formula f)

let string_of_theory {th_name=name;
                      th_const=const;
                      th_unary=unary;
                      th_binary=binary;
                      th_predicates=predicates;
                      th_relations=relations;
                      th_equations=equations;
                      th_axioms=axioms;
                      th_prop_tests=tests} =
  "Theory: " ^ name ^ "\n" ^
  "Constant: " ^ String.concat " " (Array.to_list const) ^ "\n" ^
  "Unary: " ^ String.concat " " (Array.to_list unary) ^ "\n" ^
  "Binary: " ^ String.concat " " (Array.to_list binary) ^ "\n" ^
  "Predicates: " ^ String.concat " " (Array.to_list predicates) ^ "\n" ^
  "Relations: " ^ String.concat " " (Array.to_list relations) ^ "\n" ^
  "Equations:\n" ^ String.concat "\n" (List.map (fun (_,e) -> string_of_equation e) equations) ^ "\n" ^
  "Axioms:\n" ^ String.concat "\n" (List.map string_of_formula axioms) ^ "\n" ^
  "Tests:\n" ^ String.concat "\n" (List.map string_of_propertytest tests) ^ "\n"
