import Lean

/-!
`#spec_surface thm` lists this project's definitions that the statement of
`thm` depends on, followed through definition bodies (not through proofs).
`#audit_axioms thm` lists the axioms behind `thm`. Adapted from CLAUDE.md.
-/

open Lean Elab Command

/-- Module name prefixes that belong to this project. -/
def ownPrefixes : List Name := [`Maze, `Sling, `Upload, `UploadSpec, `Verification]

partial def specSurface (env : Environment) (thm : Name) : NameSet :=
  let rec go (todo : List Name) (seen : NameSet) : NameSet :=
    match todo with
    | [] => seen
    | c :: rest =>
      if seen.contains c then go rest seen else
      let next := match env.find? c with
        | some (.defnInfo d) => d.type.getUsedConstants.toList ++ d.value.getUsedConstants.toList
        | some ci => ci.type.getUsedConstants.toList
        | none => []
      go (next ++ rest) (seen.insert c)
  match env.find? thm with
  | some ci => go ci.type.getUsedConstants.toList {}
  | none => {}

elab "#spec_surface " id:ident : command => do
  let env ← getEnv
  let thm ← liftCoreM <| realizeGlobalConstNoOverloadWithInfo id
  -- Keep definitions and types; drop constructors, recursors and generated helpers.
  let own := (specSurface env thm).toList.filter fun c =>
    !c.isInternal && !Meta.isMatcherCore env c && !isAuxRecursor env c && !isNoConfusion env c &&
    !(c matches .str _ "ctorIdx") &&
    (match env.find? c with | some (.ctorInfo _) | some (.recInfo _) => false | _ => true) &&
    match env.getModuleIdxFor? c with
    | some idx => ownPrefixes.any (·.isPrefixOf (env.header.moduleNames[idx.toNat]!))
    | none => true
  logInfo m!"{thm} depends on: {own.toArray.qsort (·.toString < ·.toString)}"

elab "#audit_axioms " id:ident : command => do
  let thm ← liftCoreM <| realizeGlobalConstNoOverloadWithInfo id
  let axs ← liftCoreM <| collectAxioms thm
  logInfo m!"{thm} axioms: {axs.toList}"
