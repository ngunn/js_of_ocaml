(* Js_of_ocaml compiler
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2010 Jérôme Vouillon
 * Laboratoire PPS - CNRS Université Paris Diderot
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

let times = Option.Debug.find "times"

let f toplevel linkall paths files js_files input_file output_file source_map =
  let t = Util.Timer.make () in
  Linker.load_files js_files;
  let paths = List.rev_append paths [Util.find_pkg_dir "stdlib"] in
  let t1 = Util.Timer.make () in
  if times () then Format.eprintf "Start parsing...@.";
  let need_debug =
    if source_map <> None || Option.Optim.debuginfo () then `Full else
    if Option.Optim.pretty () then `Names else `No
  in
  let p,d =
    match input_file with
      None ->
        Parse_bytecode.from_channel ~toplevel ~debug:need_debug ~files ~paths stdin
    | Some f ->
        let ch = open_in_bin f in
        let p,d = Parse_bytecode.from_channel ~toplevel ~debug:need_debug ~files ~paths ch in
        close_in ch;
        p,d
  in
  if times () then Format.eprintf "  parsing: %a@." Util.Timer.print t1;
  let output_program fmt = Driver.f ~toplevel ~linkall ?source_map fmt d p in
  begin match output_file with
    | None ->
      output_program (Pretty_print.to_out_channel stdout)
    | Some f ->
      let f_tmp = Filename.temp_file ~temp_dir:(Filename.dirname f) (Filename.basename f) ".tmpjs" in
      try
        let ch = open_out_bin f_tmp in
        output_program (Pretty_print.to_out_channel ch);
        close_out ch;
        (try Sys.remove f with Sys_error _ -> ());
        Sys.rename f_tmp f
      with exc ->
        Sys.remove f_tmp;
        raise exc
  end;
  if times () then Format.eprintf "compilation: %a@." Util.Timer.print t

let run () =
  Util.Timer.init Sys.time;
  let js_files = ref [] in
  let files = ref [] in
  let output_file = ref None in
  let input_file = ref None in
  let no_runtime = ref false in
  let linkall = ref false in
  let toplevel = ref false in
  let source_map = ref false in
  let show_version = ref `No in
  let paths = ref [] in
  let options =
    [
     ("-version",Arg.Unit (fun () -> show_version:=`Full) ," display version");
     ("-vnum",Arg.Unit (fun () -> show_version:=`Number) ," display version number");
     ("-debug", Arg.String Option.Debug.enable, "<name> debug module <name>");
     ("-disable",
      Arg.String Option.Optim.disable, "<name> disable optimization <name>");
     ("-enable",
      Arg.String Option.Optim.enable, "<name> enable optimization <name>");
     ("-pretty", Arg.Unit (fun () -> Option.Optim.enable "pretty"), " pretty print the output");
     ("-debuginfo", Arg.Unit (fun () -> Option.Optim.enable "debuginfo"), " output debug info");
     ("-opt", Arg.Int Driver.set_profile, "<oN> set optimization profile : o1 (default), o2, o3");
     ("-noinline", Arg.Unit (fun () -> Option.Optim.disable "inline"), " disable inlining");
     ("-linkall", Arg.Set linkall, " link all primitives");
     ("-noruntime", Arg.Unit (fun () -> no_runtime := true),
      " do not include the standard runtime");
     ("-sourcemap", Arg.Unit (fun () -> source_map := true), " generate source map");
     ("-toplevel", Arg.Set toplevel, " compile a toplevel");
     ("-tc", Arg.Symbol (List.map Option.Tailcall.to_string Option.Tailcall.all,(fun s -> Option.Tailcall.(set (of_string s)))),
      " set tailcall optimisation");
     ("-I", Arg.String (fun s -> paths := s :: !paths),
      "<dir> Add <dir> to the list of include directories");
     ("-file", Arg.String (fun s -> files:= s :: !files ),
      "<file> register <file> to the pseudo filesystem");
     ("-o", Arg.String (fun s -> output_file := Some s),
      "<file> set output file name to <file>")]
  in
  Arg.parse (Arg.align options)
      (fun s ->
         (* internal option for debugging only *)
         if s="@nofail" then Util.fail:=false
         else
         if Filename.check_suffix s ".js" then
           js_files := s :: !js_files
         else
           input_file := Some s)
    (Format.sprintf "Usage: %s [options]" Sys.argv.(0));
  let version = match Compiler_version.git_version with
    | "" -> Compiler_version.s
    | v  -> Printf.sprintf "%s+git-%s"Compiler_version.s v in
  match !show_version with
  | `Number -> Format.printf "%s@." version
  | `Full -> Format.printf "Js_of_ocaml compiler, version %s@." version
  | `No ->
  if !toplevel then linkall:=true;
  let runtime = if !no_runtime then [] else ["+runtime.js"] in
  let chop_extension s =
    try Filename.chop_extension s with Invalid_argument _ -> s in
  let output_f = match !output_file with
      Some _ -> !output_file
    | None   -> Util.opt_map (fun s -> chop_extension s ^ ".js") !input_file in
  let source_m =
    if !source_map
    then
      match output_f with
        | Some file ->
          Some (
            chop_extension file ^ ".map",
            {
              Source_map.version = 3;
              file;
              sourceroot = None;
              sources = [];
              sources_content = [];
              names = [];
              mappings = []
            })
        | None ->
          failwith "Don't know where to output the Source-map@."
    else None in
  f !toplevel !linkall !paths !files (runtime @ List.rev !js_files)
    !input_file output_f source_m


let _ =
  try run () with
  | (Match_failure _ | Assert_failure _ | Not_found) as exc ->
    let backtrace = Printexc.get_backtrace () in
    Format.eprintf
      "%s: You found a bug. \
       Please report it at https://github.com/ocsigen/js_of_ocaml/issues :@."
      Sys.argv.(0);
    Format.eprintf "Error: %s@." (Printexc.to_string exc);
    prerr_string backtrace;
    exit 1
  | Failure s ->
    Format.eprintf "%s: Error: %s@." Sys.argv.(0) s;
    exit 1
  | exc ->
    Format.eprintf "%s: Error: %s@." Sys.argv.(0) (Printexc.to_string exc);
    exit 1
