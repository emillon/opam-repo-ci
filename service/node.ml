open Current.Syntax
open Opam_repo_ci

type action = {
  job_id : Current.job_id option;
  result : [`Built | `Analysed | `Linted] Current_term.Output.t;
}

type t =
  | Root of t list
  | Branch of { label : string; action : action option; children : t list }

let status_sep = String.make 1 Opam_repo_ci_api.Common.status_sep

let job_id job =
  let+ md = Current.Analysis.metadata job in
  match md with
  | Some { Current.Metadata.job_id; _ } -> job_id
  | None -> None

let root children = Root children
let branch ~label children = Branch { label; action = None; children }
let actioned_branch ~label action children = Branch { label; action = Some action; children }
let leaf ~label action = Branch { label; action = Some action; children = [] }

let action kind job =
  let+ job_id = job_id job
  and+ result = job |> Current.map (fun _ -> kind) |> Current.state ~hidden:true
  in
  { job_id; result }

let rec flatten ~prefix acc f = function
  | Root children ->
    flatten_children ~prefix acc f children
  | Branch { label; action = None; children } ->
    let prefix = prefix ^ label ^ status_sep in
    flatten_children ~prefix acc f children
  | Branch { label; action = Some { job_id; result }; children } ->
    let prefix_children = prefix ^ label ^ status_sep in
    let label = prefix ^ label in
    Index.Job_map.add label (f ~job_id ~result) (flatten_children ~prefix:prefix_children acc f children)
and flatten_children ~prefix acc f children =
  List.fold_left (fun acc child -> flatten ~prefix acc f child) acc children

let flatten f t = flatten Index.Job_map.empty f t ~prefix:""

let pp_result f = function
  | Ok `Built -> Fmt.string f "built"
  | Ok `Analysed -> Fmt.string f "analysed"
  | Ok `Linted -> Fmt.string f "linted"
  | Error (`Active _) -> Fmt.string f "active"
  | Error (`Msg m) -> Fmt.string f m

let rec dump f = function
  | Root children ->
    Fmt.pf f "@[<v>%a@]"
      (Fmt.(list ~sep:cut) dump) children
  | Branch { label; action = None; children } ->
    Fmt.pf f "@[<v2>%s%a@]"
      label
      Fmt.(list ~sep:nop (cut ++ dump)) children
  | Branch { label; action = Some { job_id = _; result }; children } ->
    Fmt.pf f "@[<v2>%s (%a)%a@]"
      label
      pp_result result
      Fmt.(list ~sep:nop (cut ++ dump)) children
