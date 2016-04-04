(* 
Module: ColonEqualSep
  Parses generic config files that use equal or colon as separator
     i.e. 'param = value' or 'param: value'
                
Author:  Origami project (c) IBM Research 2013

 Based on mysql.aug by Tim Stoop <tim@kumina.nl>,
 which is in turn heavily based on php.aug by 
 Raphael Pinson <raphink@gmail.com>
*)

module ColonEqualSep =
  autoload xfm

(************************************************************************
 * INI File settings
 *************************************************************************)
let comment  = IniFile.comment IniFile.comment_re "#"

let sep      = IniFile.sep IniFile.sep_re IniFile.sep_default

let entry    =
     let bare = Quote.do_dquote_opt_nil (store /[^#;" \t\r\n]+([ \t]+[^#;" \t\r\n]+)*/)
  in let quoted = Quote.do_dquote (store /[^"\r\n]*[#;]+[^"\r\n]*/)
  in [ Util.indent . key IniFile.entry_re . sep . Sep.opt_space . bare . (comment|IniFile.eol) ]
   | [ Util.indent . key IniFile.entry_re . sep . Sep.opt_space . quoted . (comment|IniFile.eol) ]
   | [ Util.indent . key IniFile.entry_re . store // .  (comment|IniFile.eol) ]
   | [ Util.indent . key IniFile.entry_re . sep . Quote.do_quote (store /[^\n"]+/) . (comment|IniFile.eol) ]
   | comment


(*
let includedir = Build.key_value_line /!include(dir)?/ Sep.space (store Rx.fspath)
               . (comment|IniFile.empty)*
*)

(*
let lns    = (comment|IniFile.empty)* . (entry|includedir)*
*)

(*
let lns    = (comment|IniFile.empty)* . (entry)*
*)
let lns = (comment | IniFile.empty | entry )*

let filter = (incl "/etc/origami/equalsepgeneric.conf")

let xfm = transform lns filter

