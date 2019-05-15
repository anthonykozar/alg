(* Output in various formats. *)

module T = Theory
module A = Algebra
module C = Config

(* A formatter for output *)
type formatter = {
  header: unit -> unit;
  size_header: int -> unit;
  algebra: A.algebra -> unit;
  size_footer: unit -> unit;
  footer: (int * int) list -> unit;
  count_header: unit -> unit;
  count: int -> int -> unit;
  count_footer: (int * int) list -> unit;
  interrupted: unit -> unit                
}

module type Formatter =
sig
  val init : Config.config -> out_channel -> string list -> T.theory -> formatter
end

(* Several output styles (Markdown, LaTeX, and HTML) are sufficiently similar
   that it is worth implementing them all the same way via the following structure. *)
module type TextStyle =
sig
  val ttfont : string -> string
  val names : T.theory -> A.algebra -> string array
  val link : string -> string -> string
  val title : out_channel -> string -> unit
  val section : out_channel -> string -> unit
  val footer : out_channel -> unit
  val code : out_channel -> string list -> unit
  val warning : out_channel -> string -> unit
  val algebra_header : out_channel -> string -> string option -> string option -> unit
  val algebra_unary : out_channel -> string array -> string -> int array -> unit
  val algebra_binary : out_channel -> string array -> string -> int array array -> unit
  val algebra_predicate : out_channel -> string array -> string -> int array -> unit
  val algebra_relation : out_channel -> string array -> string -> int array array -> unit
  val algebra_footer : out_channel -> unit
  val count_header : out_channel -> unit
  val count_row : out_channel -> int -> int -> unit
  val count_footer : out_channel -> string option -> unit
end

(* A functor taking an implementation of [TextStyle] to [Formatter]. *)
module Make(S : TextStyle) : Formatter =
struct

  (* Create a URL which queries the http://oeis.org/. *)
  let oeis lst =
    let m = List.fold_left (fun m (n,_) -> max m n) 0 lst in
    let nums = String.concat ","
      (List.map (fun n -> match Util.lookup n lst with None -> "_" | Some k -> string_of_int k) (Util.enumFromTo 2 m))
    in
    let nums' = String.concat ", "
      (List.map (fun n -> match Util.lookup n lst with None -> "_" | Some k -> string_of_int k) (Util.enumFromTo 2 m))
    in
      nums', "http://oeis.org/search?q=" ^ nums
        
  let init
      {C.sizes=sizes; C.source=source}
      ch
      src_lines
      ({T.th_name=th_name; T.th_const=th_const; T.th_unary=th_unary; T.th_binary=th_binary;
        T.th_predicates=th_pred; T.th_relations=th_rel; T.th_prop_tests=th_tests} as th) =

    let count_footer lst =
      let lst = List.filter (fun (n,_) -> n >= 2) lst in
        S.count_footer ch
          (if List.length lst <= 2
           then None
           else 
             let nums, url = oeis lst in
               Some (Printf.sprintf "Check the numbers %s on-line at oeis.org\n" (S.link nums url)))
    in

      { header = 
          begin fun () ->
            S.title ch th_name ;
            if source then S.code ch src_lines
          end;

        size_header =
          begin fun n ->
            S.section ch ("Size " ^ string_of_int n)
          end;

        algebra =
          begin fun ({A.alg_name=name; A.alg_prod=prod; A.alg_const=const; A.alg_unary=unary; A.alg_binary=binary;
                      A.alg_predicates=pred; A.alg_relations=rel} as a) ->
            let name = (match name with | None -> "Model of " ^ th_name | Some n -> n) in
            let info =
              begin match prod with
                | None -> None
                | Some lst -> Some ("Decomposition: " ^ String.concat ", " (List.map S.ttfont lst))
              end
            in
            (* Evaluation of property tests sd be in algebra *)
            let props = List.map (fun (pname, pformula) -> (pname, (Check_model.check_equation a pformula))) th_tests in
            let propstext = 
              begin match props with
                | [] -> None
                | _ -> Some ("Properties: " ^ (String.concat ", " (List.map 
                              (fun (pname, ptruthval) -> if ptruthval then pname else ("not " ^ pname))
                              props)))
              end
            in
            let ns = S.names th a in
            S.algebra_header ch name info propstext ;
            Array.iteri (fun op t -> S.algebra_unary ch ns th_unary.(op) t) unary ;
            Array.iteri (fun op t -> S.algebra_binary ch ns th_binary.(op) t) binary ;
            Array.iteri (fun p t -> S.algebra_predicate ch ns th_pred.(p) t) pred ;
            Array.iteri (fun r t -> S.algebra_relation ch ns th_rel.(r) t) rel ;
            S.algebra_footer ch 
          end;

        size_footer = begin fun () -> () end;

        count_header = begin fun () -> S.count_header ch end;

        count = S.count_row ch;

        count_footer = count_footer;

        footer =
          begin fun lst ->
            S.section ch "Statistics" ;
            S.count_header ch ;
            List.iter (fun (n,k) -> S.count_row ch n k) lst ;
            count_footer lst ;
            S.footer ch
          end;

        interrupted = begin fun () -> S.warning ch "the computation was interrupted by the user" end
      }
end (* Make *)

module MarkdownStyle : TextStyle =
struct
  let ttfont str = str

  let names {T.th_const=th_const; T.th_unary=th_unary; T.th_binary=th_binary} {A.alg_size=n; A.alg_const=const} =
    let forbidden_names = Array.to_list th_const @ Array.to_list th_unary @ Array.to_list th_binary in
    let default_names = 
      ref (List.filter (fun x -> not (List.mem x forbidden_names))
             ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"; "k"; "l"; "m";
              "n"; "o"; "p"; "q"; "e"; "r"; "s"; "t"; "u"; "v"; "x"; "y"; "z";
              "A"; "B"; "C"; "D"; "E"; "F"; "G"; "H"; "I"; "J"; "K"; "L"; "M";
              "N"; "O"; "P"; "Q"; "R"; "S"; "T"; "U"; "V"; "W"; "X"; "Y"; "Z"])
    in
    let m = List.length !default_names in
    let ns = Array.make n "?" in
    (* Constants *)
    for k = 0 to Array.length th_const - 1 do ns.(const.(k)) <- th_const.(k) done ;
    for k = 0 to n-1 do
      if ns.(k) = "?" then
        ns.(k) <-
          match !default_names with
            | [] -> "x" ^ string_of_int (k - m)
            | d::ds -> default_names := ds ; d
    done ;
    ns

  let link txt url = Printf.sprintf "[%s](%s)" txt url

  let title ch str = Printf.fprintf ch "# Theory %s\n\n" str

  let section ch str = Printf.fprintf ch "# %s\n\n" str

  let footer ch = ()

  let code ch lines =
    List.iter (fun line -> Printf.fprintf ch "    %s\n" line) lines ;
    Printf.fprintf ch "\n"
      
  let warning ch msg = Printf.fprintf ch "\n\n**Warning: %s**\n\n" msg

  let algebra_header ch name info info2 =
    Printf.fprintf ch "### %s\n\n" name ;
    begin match info with
      | None -> ()
      | Some msg -> Printf.fprintf ch "%s\n\n" msg
    end ;
    begin match info2 with
      | None -> ()
      | Some msg -> Printf.fprintf ch "%s\n\n" msg
    end

  let algebra_unary ch names op t =
    let n = Array.length t in
    let w = Array.fold_left (fun w s -> max w (String.length s)) 0 names in
    let v = String.length op in
    let ds = String.make w '-' in
      Printf.fprintf ch "\n    %*s |" (max w v) op ;
      for i = 0 to n-1 do Printf.fprintf ch "  %*s" w names.(i) done ;
      Printf.fprintf ch "\n    %s-+" (String.make (max w v) '-');
      for i = 0 to n-1 do Printf.fprintf ch "--%s" ds done;
      Printf.fprintf ch "\n    %*s |" (max w v) " ";
      for i = 0 to n-1 do Printf.fprintf ch "  %*s" w names.(t.(i)) done ;
      Printf.fprintf ch "\n\n"

  let algebra_binary ch names op t =
    let n = Array.length t in
    let w = Array.fold_left (fun w s -> max w (String.length s)) 0 names in
    let v = String.length op in
    let ds = String.make w '-' in
      Printf.fprintf ch "\n    %*s |" (max w v) op;
      for i = 0 to n-1 do Printf.fprintf ch "  %*s" w names.(i) done ;
      Printf.fprintf ch "\n    %s-+" (String.make (max w v) '-') ;
      for j = 0 to n-1 do Printf.fprintf ch "--%s" ds done ;
      for i = 0 to n-1 do
        Printf.fprintf ch "\n    %*s |" (max w v) names.(i) ;
        for j = 0 to n-1 do
          Printf.fprintf ch "  %*s" w names.(t.(i).(j))
        done
      done ;
      Printf.fprintf ch "\n\n"

  let algebra_predicate ch names p t =
    let n = Array.length t in
    let w = Array.fold_left (fun w s -> max w (String.length s)) 0 names in
    let v = String.length p in
    let ds = String.make w '-' in
      Printf.fprintf ch "\n    %*s |" (max w v) p ;
      for i = 0 to n-1 do Printf.fprintf ch "  %*s" w names.(i) done ;
      Printf.fprintf ch "\n    %s-+" (String.make (max w v) '-');
      for i = 0 to n-1 do Printf.fprintf ch "--%s" ds done;
      Printf.fprintf ch "\n    %*s |" (max w v) " ";
      for i = 0 to n-1 do Printf.fprintf ch "  %*d" w t.(i) done ;
      Printf.fprintf ch "\n\n"

  let algebra_relation ch names r t =
    let n = Array.length t in
    let w = Array.fold_left (fun w s -> max w (String.length s)) 0 names in
    let v = String.length r in
    let ds = String.make w '-' in
      Printf.fprintf ch "\n    %*s |" (max w v) r;
      for i = 0 to n-1 do Printf.fprintf ch "  %*s" w names.(i) done ;
      Printf.fprintf ch "\n    %s-+" (String.make (max w v) '-') ;
      for j = 0 to n-1 do Printf.fprintf ch "--%s" ds done ;
      for i = 0 to n-1 do
        Printf.fprintf ch "\n    %*s |" (max w v) names.(i) ;
        for j = 0 to n-1 do
          Printf.fprintf ch "  %*d" w t.(i).(j)
        done
      done ;
      Printf.fprintf ch "\n\n"

  let algebra_footer ch =
    Printf.fprintf ch "\n- - - - - - - - - - - - - - - - - - - - - - - - - - - -\n\n%!" (* flush *)

  let count_header ch =
    Printf.fprintf ch "    size | count\n" ;
    Printf.fprintf ch "    -----|------\n"

  let count_row ch n k =
    Printf.fprintf ch "    %4d | %d\n%!" n k

  let count_footer ch = function
    | None -> Printf.fprintf ch "\n"
    | Some msg -> Printf.fprintf ch "\n%s\n" msg

end (* MarkdownStyle *)

module HTMLStyle : TextStyle =
struct
  let escape str = str (* TODO should escape < > & and so on. *)

  let ttfont str = "<code>" ^ escape str ^ "</code>"

  let names {T.th_const=th_const; T.th_unary=th_unary; T.th_binary=th_binary} {A.alg_size=n; A.alg_const=const} =
    let forbidden_names = Array.to_list th_const @ Array.to_list th_unary @ Array.to_list th_binary in
    let default_names = 
      ref (List.filter (fun x -> not (List.mem x forbidden_names))
             ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"; "k"; "l"; "m";
              "n"; "o"; "p"; "q"; "e"; "r"; "s"; "t"; "u"; "v"; "x"; "y"; "z";
              "A"; "B"; "C"; "D"; "E"; "F"; "G"; "H"; "I"; "J"; "K"; "L"; "M";
              "N"; "O"; "P"; "Q"; "R"; "S"; "T"; "U"; "V"; "W"; "X"; "Y"; "Z"])
    in
    let m = List.length !default_names in
    let ns = Array.make n "?" in
    (* Constants *)
    for k = 0 to Array.length th_const - 1 do ns.(const.(k)) <- th_const.(k) done ;
    for k = 0 to n-1 do
      if ns.(k) = "?" then
        ns.(k) <-
          match !default_names with
            | [] -> "x" ^ string_of_int (k - m)
            | d::ds -> default_names := ds ; d
    done ;
    ns

  let link txt url = Printf.sprintf "<a href=\"%s\">%s</a>" url txt

  let title ch str = Printf.fprintf ch "<html>\n<head>\n<title>Theory %s</title>\n</head>\n<body>\n<h1>Theory <tt>%s</tt></h1>\n\n" str str

  let section ch str = Printf.fprintf ch "<h2>%s</h2>\n\n" str

  let footer ch = Printf.fprintf ch "\n</body>\n</html>\n"

  let code ch lines =
    Printf.fprintf ch "\n<pre>\n" ;
    List.iter (fun line -> Printf.fprintf ch "%s\n" line) lines ;
    Printf.fprintf ch "</pre>\n"
      
  let warning ch msg = Printf.fprintf ch "\n\n<blockquote><b>Warning: %s</b></blockquote>\n\n" msg

  let algebra_header ch name info info2 =
    Printf.fprintf ch "<h3>%s</h3>\n\n" name ;
    begin match info with
      | None -> ()
      | Some msg -> Printf.fprintf ch "<p>%s</p>\n\n" msg
    end ;
    begin match info with
      | None -> ()
      | Some msg -> Printf.fprintf ch "<p>%s</p>\n\n" msg
    end

  let algebra_unary ch names op t =
    let n = Array.length t in
      Printf.fprintf ch "\n<p><table style=\"border-collapse: collapse\" cellpadding=\"5\" border=\"1\">\n<tr><th><code>%s</code></th>" op ;
      for i = 0 to n-1 do Printf.fprintf ch "<th><code>%s</code></th>" names.(i) done ;
      Printf.fprintf ch "</tr>\n<tr><td>&nbsp;</td>" ;
      for i = 0 to n-1 do Printf.fprintf ch "<td><code>%s</code></td>" names.(t.(i)) done ;
      Printf.fprintf ch "</tr>\n</table></p>\n\n"

  let algebra_binary ch names op t =
    let n = Array.length t in
      Printf.fprintf ch "\n<p><table style=\"border-collapse: collapse\"  cellpadding=\"5\" border=\"1\">\n<tr><th><code>%s</code></th>" op;
      for i = 0 to n-1 do Printf.fprintf ch "<th><code>%s</code></th>" names.(i) done ;
      Printf.fprintf ch "</tr>\n" ;
      for i = 0 to n-1 do
        Printf.fprintf ch "<tr><th><code>%s</code></th>" names.(i) ;
        for j = 0 to n-1 do
          Printf.fprintf ch "<td><code>%s</code></td>" names.(t.(i).(j))
        done ;
        Printf.fprintf ch "</tr>\n"
      done ;
      Printf.fprintf ch "</table></p>\n\n"

  let algebra_predicate ch names p t =
    let n = Array.length t in
      Printf.fprintf ch "\n<p><table style=\"border-collapse: collapse\" cellpadding=\"5\" border=\"1\">\n<tr><th><code>%s</code></th>" p ;
      for i = 0 to n-1 do Printf.fprintf ch "<th><code>%s</code></th>" names.(i) done ;
      Printf.fprintf ch "</tr>\n<tr><td>&nbsp;</td>" ;
      for i = 0 to n-1 do Printf.fprintf ch "<td><code>%d</code></td>" t.(i) done ;
      Printf.fprintf ch "</tr>\n</table></p>\n\n"

  let algebra_relation ch names r t =
    let n = Array.length t in
      Printf.fprintf ch "\n<p><table style=\"border-collapse: collapse\"  cellpadding=\"5\" border=\"1\">\n<tr><th><code>%s</code></th>" r;
      for i = 0 to n-1 do Printf.fprintf ch "<th><code>%s</code></th>" names.(i) done ;
      Printf.fprintf ch "</tr>\n" ;
      for i = 0 to n-1 do
        Printf.fprintf ch "<tr><th><code>%s</code></th>" names.(i) ;
        for j = 0 to n-1 do
          Printf.fprintf ch "<td><code>%d</code></td>" t.(i).(j)
        done ;
        Printf.fprintf ch "</tr>\n"
      done ;
      Printf.fprintf ch "</table></p>\n\n"

  let algebra_footer ch = Printf.fprintf ch "\n\n%!"

  let count_header ch =
    Printf.fprintf ch "<table  style=\"border-collapse: collapse\" cellpadding=\"5\" border=\"1\">\n<tr><th>Size</th><th>Count</th></tr>\n"

  let count_row ch n k =
    Printf.fprintf ch "<tr><td align=\"center\"><code>%d</code></td><td align=\"center\"><code>%d</code></td></tr>\n" n k

  let count_footer ch = function
    | None -> Printf.fprintf ch "</table>"
    | Some msg -> Printf.fprintf ch "</table>\n<p>%s</p>\n" msg

end (* HTMLStyle *)

module LaTeXStyle : TextStyle =
struct

  (* Escape LaTeX special characters. This is horribly inefficient, but it does not matter,
     as it is only done once. *)
  let escape str =
    let trans = [
      ('_', "{\\_}");
      ('$', "{\\$}");
      ('%', "{\\%}");
      ('&', "{\\&}");
      ('*', "{*}");
      ('+', "{+}");
      ('-', "{-}");
      ('/', "{/}");
      ('\\',"{\\backslash}");
      (':', "{:}");
      ('<', "{<}");
      ('=', "{=}");
      ('>', "{>}");
      ('?', "{?}");
      ('@', "{@}");
      ('^', "{\\^}");
      ('|', "{:}");
      ('~', "{\\char126}");
    ]
    in
    let s = ref "" in
    String.iter
      (fun c -> s := !s ^ (try List.assoc c trans with Not_found -> String.make 1 c))
      str ;
    !s

  let ttfont str = "\\texttt{" ^ escape str ^ "}"
  let math str = "$" ^ str ^ "$"

  let names {T.th_const=th_const; T.th_unary=th_unary; T.th_binary=th_binary} {A.alg_size=n; A.alg_const=const} =
    let forbidden_names = Array.to_list th_const @ Array.to_list th_unary @ Array.to_list th_binary in
    let default_names = 
      ref (List.filter (fun x -> not (List.mem x forbidden_names))
             ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"; "k"; "l"; "m";
              "n"; "o"; "p"; "q"; "e"; "r"; "s"; "t"; "u"; "v"; "x"; "y"; "z";
              "A"; "B"; "C"; "D"; "E"; "F"; "G"; "H"; "I"; "J"; "K"; "L"; "M";
              "N"; "O"; "P"; "Q"; "R"; "S"; "T"; "U"; "V"; "W"; "X"; "Y"; "Z"])
    in
    let m = List.length !default_names in
    let ns = Array.make n "?" in
    (* Constants *)
    for k = 0 to Array.length th_const - 1 do ns.(const.(k)) <- math th_const.(k) done ;
    for k = 0 to n-1 do
      if ns.(k) = "?" then
        ns.(k) <-
          match !default_names with
            | [] -> math ("x_" ^ string_of_int (k - m))
            | d::ds -> default_names := ds ; math d
    done ;
    ns
      
  let link txt url = txt
    
  let title ch str =
    Printf.fprintf ch
      "\\documentclass{article}\n\\begin{document}\n\\title{Theory \\texttt{%s}}\n\\author{Computed by alg}\n\\maketitle\n\\parindent=0pt\\parskip=\\baselineskip\n" (escape str)

  let section ch str = Printf.fprintf ch "\\section*{%s}\n" str

  let footer ch = Printf.fprintf ch "\n\\end{document}\n"

  let code ch lines =
    Printf.fprintf ch "\n\\begin{verbatim}\n" ;
    List.iter (fun line -> Printf.fprintf ch "%s\n" line) lines ;
    Printf.fprintf ch "\\end{verbatim}\n"
      
  let warning ch msg = Printf.fprintf ch "\\begin{center}\\textbf{Warning: %s}\\end{center}\n" msg

  let algebra_header ch name info info2 =
    Printf.fprintf ch "\\subsection*{%s}\n\n" (escape name) ;
    begin match info with
      | None -> ()
      | Some msg -> Printf.fprintf ch "\n\n\\noindent\n%s\n\n" msg
    end ;
    begin match info2 with
      | None -> ()
      | Some msg -> Printf.fprintf ch "\n\n\\noindent\n%s\n\n" msg
    end

  let algebra_unary ch names op t =
    let n = Array.length t in
    Printf.fprintf ch "\\begin{tabular}[t]{|" ;
    for i = 0 to n do Printf.fprintf ch "c|" done ;
    Printf.fprintf ch "}\n\\hline\n" ;
    Printf.fprintf ch "%s " (ttfont op);
    for i = 0 to n-1 do Printf.fprintf ch "& %s " names.(i) done ;
    Printf.fprintf ch "\\\\ \\hline\n" ;
    for i = 0 to n-1 do Printf.fprintf ch "& %s " names.(t.(i)) done ;
    Printf.fprintf ch "\\\\ \\hline\n\\end{tabular}\n\n"

  let algebra_binary ch names op t =
    let n = Array.length t in
    Printf.fprintf ch "\\begin{tabular}[t]{|" ;
    for i = 0 to n do Printf.fprintf ch "c|" done ;
    Printf.fprintf ch "}\n\\hline\n" ;
    Printf.fprintf ch "%s " (ttfont op);
    for i = 0 to n-1 do Printf.fprintf ch "& %s " names.(i) done ;
    Printf.fprintf ch "\\\\ \\hline\n" ;
    for i = 0 to n-1 do
      Printf.fprintf ch "%s " names.(i) ;
      for j = 0 to n-1 do
        Printf.fprintf ch "& %s " names.(t.(i).(j))
      done ;
      Printf.fprintf ch "\\\\ \\hline\n"
    done ;
    Printf.fprintf ch "\\end{tabular}\n\n"

  let algebra_predicate ch names p t =
    let n = Array.length t in
    Printf.fprintf ch "\\begin{tabular}[t]{|" ;
    for i = 0 to n do Printf.fprintf ch "c|" done ;
    Printf.fprintf ch "}\n\\hline\n" ;
    Printf.fprintf ch "%s " (ttfont p);
    for i = 0 to n-1 do Printf.fprintf ch "& %s " names.(i) done ;
    Printf.fprintf ch "\\\\ \\hline\n" ;
    for i = 0 to n-1 do Printf.fprintf ch "& %d " t.(i) done ;
    Printf.fprintf ch "\\\\ \\hline\n\\end{tabular}\n\n"

  let algebra_relation ch names r t =
    let n = Array.length t in
    Printf.fprintf ch "\\begin{tabular}[t]{|" ;
    for i = 0 to n do Printf.fprintf ch "c|" done ;
    Printf.fprintf ch "}\n\\hline\n" ;
    Printf.fprintf ch "%s " (ttfont r);
    for i = 0 to n-1 do Printf.fprintf ch "& %s " names.(i) done ;
    Printf.fprintf ch "\\\\ \\hline\n" ;
    for i = 0 to n-1 do
      Printf.fprintf ch "%s " names.(i) ;
      for j = 0 to n-1 do
        Printf.fprintf ch "& %d " t.(i).(j)
      done ;
      Printf.fprintf ch "\\\\ \\hline\n"
    done ;
    Printf.fprintf ch "\\end{tabular}\n\n"

  let algebra_footer ch = Printf.fprintf ch "\n\n%!"

  let count_header ch =
    Printf.fprintf ch "\\begin{tabular}{|c|c|}\n\\hline\nSize & Count \\\\ \\hline\n"

  let count_row ch n k =
    Printf.fprintf ch "%d & %d \\\\ \\hline" n k

  let count_footer ch _ =
    Printf.fprintf ch "\\end{tabular}\n\n"

end (* LaTeXStyle *)

(* The actual formatters for Markdown, HTML and LaTeX. *)
module Markdown = Make(MarkdownStyle)
module HTML = Make(HTMLStyle)
module LaTeX = Make(LaTeXStyle)

(* The json formatter is different from the others, so we implement it directly. *)
module JSON : Formatter =
struct
  let sep i n = if i < n then ", " else ""

  let init config ch _
      {T.th_name=th_name; T.th_const=th_const; T.th_unary=th_unary; T.th_binary=th_binary;
       T.th_predicates=th_pred; T.th_relations=th_rel} =

    {
      header = begin fun () -> Printf.fprintf ch "[ \"%s\"" th_name end;

      size_header = begin fun _ -> () end;

      algebra =
        begin
          fun {A.alg_const=const; A.alg_unary=unary; A.alg_binary=binary; A.alg_predicates=pred; A.alg_relations=rel} ->
            Printf.fprintf ch ",\n  {\n";
            Array.iteri (fun i c -> Printf.fprintf ch "    \"%s\" : %d,\n" c const.(i)) th_const;
            let ulen = Array.length unary in
            Array.iteri
              (fun op t -> 
                let n = Array.length t in
                Printf.fprintf ch "    \"%s\" : [" th_unary.(op) ;
                for i = 0 to n-1 do Printf.fprintf ch "%d%s" t.(i) (sep i (n-1)) done;
                Printf.fprintf ch "]%s\n" (sep op ulen)
              )
              unary;
           let blen = Array.length binary in
            Array.iteri
              (fun op t -> 
                let n = Array.length t in
                Printf.fprintf ch "    \"%s\" :\n      [\n" th_binary.(op) ;
                for i = 0 to n-1 do
                  Printf.fprintf ch "        [" ;
                  for j = 0 to n-1 do Printf.fprintf ch "%d%s" t.(i).(j) (sep j (n-1)) done ;
                  Printf.fprintf ch "]%s\n" (sep i (n-1))
                done ;
                Printf.fprintf ch "      ]%s\n" (sep op (blen-1))
              )
              binary;
            let plen = Array.length pred in
            Array.iteri
              (fun p t -> 
                let n = Array.length t in
                Printf.fprintf ch "    \"%s\" : [" th_pred.(p) ;
                for i = 0 to n-1 do
                  Printf.fprintf ch "%s%s" (if t.(i) = 1 then "true" else "false") (sep i (n-1))
                done;
                Printf.fprintf ch "]%s\n" (sep p plen))
              pred;
           let rlen = Array.length rel in
            Array.iteri
              (fun r t -> 
                let n = Array.length t in
                Printf.fprintf ch "    \"%s\" :\n      [\n" th_rel.(r) ;
                for i = 0 to n-1 do
                  Printf.fprintf ch "        [" ;
                  for j = 0 to n-1 do
                    Printf.fprintf ch "%s%s" (if t.(i).(j) = 1 then "true" else "false") (sep j (n-1))
                  done ;
                  Printf.fprintf ch "]%s\n" (sep i (n-1))
                done ;
                Printf.fprintf ch "      ]%s\n" (sep r (rlen-1)))
              rel;
            Printf.fprintf ch "  }"
        end;

      size_footer = begin fun () -> () end;

      footer = begin fun _ -> Printf.fprintf ch "]\n" end;

      count_header = begin fun () -> () end;

      count = begin fun n k -> () end;

      count_footer = begin fun lst ->
        Printf.fprintf ch
          ",\n  [%s]\n]\n"
          (String.concat ", " (List.map (fun (n,k) -> "[" ^ string_of_int n ^ "," ^ string_of_int k ^ "]") lst))
      end;

      interrupted = begin fun () -> Error.fatal "interrupted by the user while producing JSON output" end;
    }
end
