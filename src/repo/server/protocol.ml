(***********************************************************************)
(*                                                                     *)
(*    Copyright 2012 OCamlPro                                          *)
(*    Copyright 2012 INRIA                                             *)
(*                                                                     *)
(*  All rights reserved.  This file is distributed under the terms of  *)
(*  the GNU Public License version 3.0.                                *)
(*                                                                     *)
(*  TypeRex is distributed in the hope that it will be useful,         *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of     *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the      *)
(*  GNU General Public License for more details.                       *)
(*                                                                     *)
(***********************************************************************)

type client_to_server =
  | ClientVersion of string (* client version *)
  | GetList
  | GetOPAM    of string (* name *) * string (* version *)
  | GetDescr   of string (* name *) * string (* version *)
  | GetArchive of string (* name *) * string (* version *)
  | NewPackage of string (* name *) * string (* version *)
                * string (* opam *) * string (* descr *)
                * string (* archive *)
  | NewVersion of string (* name *) * string (* version *)
                * string (* opam *) * string (* descr *)
                * string (* archive *) * string (* key *)

type server_to_client =
  | ServerVersion of string (* server version *)
  | PackageList   of (string (* name *) * string (* version *)) list
  | OPAM          of string (* opam *)
  | Descr         of string (* descr *)
  | Archive       of string (* archive *)
  | Key           of string (* key *)
  | OK
  | Error         of string (* server error *)

let default_port = 9999

let pack_byte b n =
  output_byte b n

let unpack_byte b =
  input_byte b

(* Adapted from core binary_packing.ml *)
let pack_of_int i =
  let v = Int64.of_int i in
  let top3 = Int64.to_int (Int64.shift_right v 40) in
  let mid3 = Int64.to_int (Int64.shift_right v 16) in
  let bot2 = Int64.to_int v in
  let buf = String.create 8 in
  buf.[0] <- Char.unsafe_chr (0xFF land (top3 lsr 16));
  buf.[1] <- Char.unsafe_chr (0xFF land (top3 lsr 8));
  buf.[2] <- Char.unsafe_chr (0xFF land top3);
  buf.[3] <- Char.unsafe_chr (0xFF land (mid3 lsr 16));
  buf.[4] <- Char.unsafe_chr (0xFF land (mid3 lsr 8));
  buf.[5] <- Char.unsafe_chr (0xFF land mid3);
  buf.[6] <- Char.unsafe_chr (0xFF land (bot2 lsr 8));
  buf.[7] <- Char.unsafe_chr (0xFF land bot2);
  buf

let pack_int b i =
  output_string b (pack_of_int i)

(* Adapted from core binary_packing.ml *)
let unpack_int b =
  let buf = String.create 8 in
  really_input b buf 0 8;
  let i = Int64.logor
    (Int64.logor
       (Int64.shift_left
          (Int64.of_int (Char.code buf.[0] lsl 16
                         lor Char.code buf.[1] lsl 8
                         lor Char.code buf.[2]))
          40)
       (Int64.shift_left
          (Int64.of_int (Char.code buf.[3] lsl 16
                         lor Char.code buf.[4] lsl 8
                         lor Char.code buf.[5]))
          16))
    (Int64.of_int (Char.code buf.[6] lsl 8
                   lor Char.code buf.[7])) in
  Int64.to_int i

let pack_string b s =
  pack_int b (String.length s);
  output_string b s

let pack_strings b l =
  List.iter (pack_string b) l

let unpack_string b =
  let n = unpack_int b in
  let s = String.create n in
  really_input b s 0 n;
  s

exception Bad_packet of int

module Client_to_server = struct

  let int_of_t = function
    | ClientVersion _ -> 0
    | GetList         -> 1
    | GetOPAM _       -> 2
    | GetDescr _      -> 3
    | GetArchive _    -> 4
    | NewPackage _    -> 5
    | NewVersion _    -> 6

  let args_of_t = function
    | ClientVersion v -> [v]
    | GetList -> []
    | GetOPAM (n,v)
    | GetDescr (n,v)
    | GetArchive (n,v)-> [n;v]
    | NewPackage (n,v,o,d,a) -> [n;v;o;d;a]
    | NewVersion (n,v,o,d,a,k) -> [n;v;o;d;a;k]

  let to_channel chan t =
    pack_byte chan (int_of_t t);
    pack_strings chan (args_of_t t)

  let of_channel chan =
    match unpack_byte chan with
    | 0 -> ClientVersion (unpack_string chan)
    | 1 -> GetList
    | 2 ->
        let n = unpack_string chan in
        let v = unpack_string chan in
        GetOPAM (n, v)
    | 3 ->
        let n = unpack_string chan in
        let v = unpack_string chan in
        GetDescr (n, v)
    | 4 ->
        let n = unpack_string chan in
        let v = unpack_string chan in
        GetArchive (n, v)
    | 5 ->
        let n = unpack_string chan in
        let v = unpack_string chan in
        let o = unpack_string chan in
        let d = unpack_string chan in
        let a = unpack_string chan in
        NewPackage (n, v, o, d, a)
    | 6 ->
        let n = unpack_string chan in
        let v = unpack_string chan in
        let o = unpack_string chan in
        let d = unpack_string chan in
        let a = unpack_string chan in
        let k = unpack_string chan in
        NewVersion (n, v, o, d, a, k)
    | i ->
        raise (Bad_packet i)

end

module Server_to_client = struct


  let int_of_t = function
    | ServerVersion _ -> 0
    | PackageList _   -> 1
    | OPAM _          -> 2
    | Descr _         -> 3
    | Archive _       -> 4
    | Key _           -> 5
    | OK              -> 6
    | Error _         -> 7

  let args_of_t = function
    | PackageList l ->
        let p accu (n,v) = v :: n :: accu in
        pack_of_int (List.length l) :: List.fold_left p [] l
    | ServerVersion s
    | OPAM s
    | Descr s
    | Archive s
    | Key s
    | Error s -> [s]
    | OK -> []

  let to_channel chan t =
    pack_byte chan (int_of_t t);
    pack_strings chan (args_of_t t)

  let of_channel chan =
    match unpack_byte chan with
    | 0 -> ServerVersion (unpack_string chan)
    | 1 ->
        let n = unpack_int chan in
        let rec aux accu = function
          | 0 -> List.rev accu
          | k ->
              let n = unpack_string chan in
              let v = unpack_string chan in
              aux ((n, v) :: accu) (k-1) in
        PackageList (aux [] n)
    | 2 -> OPAM (unpack_string chan)
    | 3 -> Descr (unpack_string chan)
    | 4 -> Archive (unpack_string chan)
    | 5 -> Key (unpack_string chan)
    | 6 -> OK
    | 7 -> Error (unpack_string chan)
    | i -> raise (Bad_packet i)
end

module Client = struct

  let write stdout t =
    Client_to_server.to_channel stdout t;
    flush stdout

  let read stdin =
    Server_to_client.of_channel stdin

  let process (stdin, stdout) t =
    write stdout t;
    read stdin

end

let process_client = Client.process

module Server = struct

  let write stdout t =
    Server_to_client.to_channel stdout t;
    flush stdout

  let read stdin =
    Client_to_server.of_channel stdin

  let process (stdin, stdout) fn =
    let r = read stdin in
    write stdout (fn r)

end

let process_server = Server.process