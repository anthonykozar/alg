(*Included groups reader/writer and helping functions.*)

let search_inverse table i size my_unit=
	let lis = table in
	let rec pomo1 lis j =
		match lis with
			| [] -> [] (*not going to happen.*)
			| h::x -> if (j < i * size) then pomo1 x (j + 1) else x
	in
	let rec pomo2 lis j = match lis with
		| [] -> Error.usage_error "A group does not have a unit."
		| h::x -> if j < size then (if h = my_unit then j else pomo2 x (j+1)) else Error.usage_error "A group does not have a unit."
	in
	pomo (pomo lis 0) 0
in
let find_unit table size =
	let head = hd table in
	let rec find table size i k = match table with
		| [] -> if k = size then i else Error.usage_error "A group does not have a unit."
		| h::x -> if k <> size then 
					(if head = hd then find x size i (k+1) else 
						(for z = 0 to (size - k - 1) do
							x = tl x;
						done
						head = hd x ;
						find x size (i + 1) 0)
					)
					else i
	in
	find table size 0 0
in
let fill binary table size=
	let rec fil binary table i j =
		match table with
			| [] -> binary
			| h::x ->  ( if j = size then j = 0; i = i + 1; else j = j + 1; done
						 binary.(i * size).j = h;
						 fil binary x i j)
	in
	fil binary table 0 -1
in
let rec substract_list table c = 
	match table with
		| [] -> []
		| h::x -> (h-c):: (substract_list table c)
in

(*??? Do we want to rename elements, so that 0 is always the unit?*)
let read () = 
	let algebras : (int*Algebra.algebra) list = [] in
	List.iter (fun size -> 
		try 
			let ic = open_in (string_of_int size) in
		with Sys_error msg -> Error.runtime_error "could not read %s" msg ;
		try
			while true; do
				let line = input_line ic in
				let table = split ("\t") line in
				table = substract_list table 1; (*Substract 1 from all elements, because they range from 1 to n instead from 0 to n-1.*)
				
				let my_unit = find_unit table size in
				let unary = Array.make_matrix (1) size (-1) in
				for i = 0 to size do
					unary.1.i = search_inverse table i size my_unit;
				done
				let binary = Array.init (1) (fun i -> Array.create_matrix size size (-1)) in
				binary = fill binary table size;
				let predicates = Array.make_matrix (0) size (-1) in (*this is an 0x0 matrix*)
				let relations = Array.init (0) (fun i -> Array.create_matrix size size (-1)) in
				
				let algebra : Algebra.algebra = {
					alg_name = None;
					alg_prod = None;
					alg_size = size;
					alg_const = Array.init (size) (fun i -> i) ;
					alg_unary = unary;
					alg_binary = binary;
					alg_predicates = predicates;
					alg_relations = relations;
					}
				in
				append algebras (size, algebra);
			done
		with End_of_file ->
			close_in ic; ) Config.groups ;
	algebras
