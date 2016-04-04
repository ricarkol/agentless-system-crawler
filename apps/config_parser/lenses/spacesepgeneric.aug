(*
Module: SpaceSepGeneric
  Parses generic config files that use spaces as separator
  i.e. param value

Author:  Origami project (c) IBM Research 2013
Based on Redis module by Marc Fournier <marc.fournier@camptocamp.com>

About: Reference
    This lens is based on config values using space as separator

About: Usage Example
(start code)
augtool> set /augeas/load/Redis/incl "/etc/redis/redis.conf"
augtool> set /augeas/load/Redis/lens "Redis.lns"
augtool> load

augtool> get /files/etc/redis/redis.conf/vm-enabled
/files/etc/redis/redis.conf/vm-enabled = no
augtool> print /files/etc/redis/redis.conf/rename-command[1]/
/files/etc/redis/redis.conf/rename-command
/files/etc/redis/redis.conf/rename-command/from = "CONFIG"
/files/etc/redis/redis.conf/rename-command/to = "CONFIG2"

augtool> set /files/etc/redis/redis.conf/activerehashing no
augtool> save
Saved 1 file(s)
augtool> set /files/etc/redis/redis.conf/save[1]/seconds 123
augtool> set /files/etc/redis/redis.conf/save[1]/keys 456
augtool> save
Saved 1 file(s)
(end code)
   The <Test_Redis> file also contains various examples.

*)

module SpaceSepGeneric =
autoload xfm

let k = Rx.word
let v = /[^\n"]+/
let comment = Util.comment
let empty = Util.empty
let indent = Util.indent
let eol = Util.eol
let del_ws_spc = Util.del_ws_spc

(* View: standard_entry
A standard entry is a key-value pair, separated by blank space, with optional
blank spaces at line beginning & end. The value part can be optionally enclosed
in single or double quotes. Comments at end-of-line are treated as part of value.
*)
let standard_entry =  [ indent . key k . del_ws_spc . Quote.do_quote_opt_nil (store v) . eol ]
let quoted_entry =  [ indent . key k . del_ws_spc . Quote.do_quote (store v) . eol ]


let entry = standard_entry | quoted_entry

(* View: lns
The lens
*)
let lns = (comment | empty | entry )*

let filter = incl "/etc/origami/spacesepgeneric.conf"

let xfm = transform lns filter
