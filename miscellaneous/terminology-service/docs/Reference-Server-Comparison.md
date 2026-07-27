# Reference-Server Comparison — using tx.fhir.org as an executable oracle

**Date:** 2026-07-24 · **Reference:** `https://tx.fhir.org/r4` (SNOMED International
core `900000000000207008/20250201` — the same edition we import; LOINC) · **Ours:**
`http://localhost:9090/fhir/r4` · **Validator:** HL7 `validator_cli.jar` v6.9.12,
FHIR R4, structural (`-tx n/a`).

This document is the answer to a question the team keeps circling: *"how do we know
which mappings are actually wrong, and what the right value is?"* Instead of arguing
about mappings in the abstract, we diff our responses against a reference server that
the FHIR community treats as authoritative. **The reference server is the spec made
executable** — it tells us both *that* something is wrong and *what the correct value
is*, field by field.

---

## The core idea (say this to the mentors first)

We check our terminology service on **three layers**, and each layer catches things
the one below it cannot:

1. **Structural validator** — is the response even valid FHIR? (shape, types,
   required fields). Catches S1–S6.
2. **Reference-server control** — run the *same* validator on **tx.fhir.org's** own
   responses. This is a **control group**: if the reference passes where we fail, our
   error is a *real defect*, not validator noise. If the reference also trips a rule,
   that rule is noise we can ignore.
3. **Oracle diff (the mapping layer)** — field-by-field compare our response to the
   reference's. This is where "mappings" stops being a vague chore and becomes a
   **finite, evidence-backed checklist**: every difference is either a gap to fill or
   a defect to fix, with the correct value sitting right there in the reference.

**The punchline for the team:** a response can *pass* the validator and still be
*wrong*. `$lookup` for LOINC passes the validator on both servers (0 errors) — yet
ours is missing designations and emits axis properties as display strings instead of
LOINC Part codes. The validator can't see that. **Only the oracle diff can.** So
"do the mappings" isn't busywork we do *instead* of conformance testing — it's the
third and deepest conformance layer, and now it has a source of truth.

Why we can't just run the HL7 `fhir-tx-ecosystem-ig` test suite against ours: that
suite is built to exercise a server that already implements the full tx ecosystem
(implicit value sets, the `tx-ecosystem` operations, specific version negotiation).
Ours is a subset, so most of the suite would fail on unimplemented surface rather
than on the things we care about. But the suite's *oracle* — tx.fhir.org — is
exactly what we use here. We get the mapping answers without needing to pass the
whole suite.

---

## What the control group proved (fresh run, 2026-07-24)

Same codes as the structural audit: SNOMED `73211009` (Diabetes mellitus), root
`138875005`; LOINC `100011-6`. Every response below is validated with the identical
`validator_cli.jar -tx n/a` command.

| Operation | Ours (validator) | Reference (validator) | Verdict |
|---|---|---|---|
| `$lookup` SNOMED | ❌ **2 errors** (S1: empty `part:[]`) | ✅ 0 errors | **Real defect** — reference clean where we fail |
| `$lookup` LOINC | ✅ 0 errors | ✅ 0 errors | Both valid — but ours has **mapping gaps** the validator can't see (see oracle diff) |
| `$lookup` invalid code | ❌ **1 error** (S2: `404` in issue-type system) | ✅ 0 errors | **Real defect** — reference uses `not-found` |
| `$subsumes` | ✅ 0 errors | ✅ 0 errors | **Both pass, but values differ** — validator is *blind* here (B7). Oracle catches it. |
| `$expand` | ❌ (S4, per audit) | ✅ 0 errors, `contains[]` all carry `system` | **Real defect** — reference shows the exact missing field |

All the warnings on both sides (`Unable to validate code … running without terminology
services`) are pure `-tx n/a` artifacts, present on the reference too → confirmed noise.

### The three failure modes, each shown live

- **Validator catches it, reference is clean → real defect.**
  `$lookup` invalid code:
  - Ours: `issue.code:"required"`, `details.coding.code:"404"` under
    `http://hl7.org/fhir/issue-type` → validator error *"Unknown code '404'"*.
  - Reference: `issue.code:"not-found"`, human text only, **0 errors**.
  - The fix *and* the correct value are both handed to us.

- **Validator is blind, only the oracle catches it.** `$subsumes(138875005, 73211009)`:
  - Ours: `{"outcome":"subsumed"}` — **not a valid `ConceptSubsumptionOutcome`**.
  - Reference: `{"outcome":"subsumes"}` — valid, and correct (root subsumes diabetes).
  - Both responses **pass the validator** (the outcome is a bare `valueCode` with no
    binding the validator can check). Without the reference we'd never know ours is
    wrong. This is B7, and it's the single best argument for why the oracle layer
    exists.

- **Validator passes both, but ours is impoverished → mapping gaps.** `$lookup` (below).

---

## The mapping oracle — SNOMED `$lookup(73211009)`, ours vs reference

Ours: 1377 bytes. Reference: 6161 bytes. The size gap *is* the finding. Field by field:

| Field | Ours | Reference (the answer key) | Action |
|---|---|---|---|
| `code` / `system` / `version` params | ❌ absent | ✅ all present | add them |
| `name` | `"73211009"` (the code) | system display name + version URI | fix source |
| `abstract` | ❌ absent | ✅ `false` | add |
| active status | `property "active"` → **empty `part:[]`** (S1 error) | `property "inactive"` = `false` (boolean) | rename + emit `valueBoolean` |
| `definitionStatusId` | `"900000000000074008"` as valueString | (surfaced as `sufficientlyDefined` boolean) | map to standard property |
| `module` | `moduleId` = `"…207008"` **valueString** | `module` = `"…207008"` **valueCode** (+ description) | fix name + type |
| `effectiveTime` | `"20020131"` **valueString** (raw RF2) | `"2002-01-31"` **valueDateTime** (ISO) | fix type + format |
| hierarchy | ❌ none | ✅ 2 `parent` + ~18 `child`, each with a display | emit from closure table |
| attribute rels | ❌ none | ✅ 4 finding-site (`363698007`) w/ `code-display:"Finding site"` | emit |
| designations | FSN + 2 synonyms | + inactive synonym **marked** `status:inactive` | mark inactive designations |

Every row is a concrete, checkable task with a known-correct target value. That is
the difference between "mappings mappings mappings" and a **closed to-do list**.

For LOINC `$lookup(100011-6)` the same method surfaces M2 (axis properties emitted as
display strings like `"Find"`/`"Pt"` instead of Part codes `LP6813-2`; `COMPONENT`
missing entirely) and M4 (no designations) — none of which the validator flags,
because the response is structurally valid. Details in
[Conformance-Audit-Results.md](Conformance-Audit-Results.md) §"Mapping verification".

---

## How to reproduce (one command per response)

```bash
OURS="http://localhost:9090/fhir/r4"; REF="https://tx.fhir.org/r4"; H="Accept: application/fhir+json"
# capture the same operation from both servers
curl -s "$REF/CodeSystem/\$lookup?system=http://snomed.info/sct&code=73211009" -H "$H" > ref.json
curl -s "$OURS/CodeSystem/\$lookup?system=http://snomed.info/sct&code=73211009" -H "$H" > ours.json
# run the identical structural validator on each; compare error counts
java -jar validator_cli.jar ours.json ref.json -version 4.0.1 -tx n/a
```

Operations covered live: `$lookup` (valid + invalid), `$subsumes`, `$expand`.
`$find-code` is our custom operation — tx.fhir.org has no equivalent, so it has no
reference control (validate it structurally only; see audit S3/B1/B5/B6).

---

## Bottom line for mentors and team

- The validator alone is **necessary but not sufficient** — it passed `$subsumes`
  and both `$lookup`s that are actually wrong.
- Using tx.fhir.org as an oracle gives us, for every operation: (a) proof our
  validator errors are real, not noise, and (b) the **correct value** for every
  field we get wrong — turning the mapping work into a finite checklist instead of an
  open-ended debate.
- Next mapping fixes, in priority order, all have a reference target now:
  S1/M1 (boolean properties), S2 (issue-type codes), B7 (subsumption outcome),
  S4 (expand `system`), then M2–M5 (LOINC Part codes, hierarchy, types).
