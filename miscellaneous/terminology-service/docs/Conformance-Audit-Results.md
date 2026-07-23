# FHIR Conformance Audit — Results (structural pass)

Validator: HL7 `validator_cli.jar` v6.9.12 · FHIR R4 (`-version 4.0.1`) ·
structural only (`-tx n/a`). Behavioural and semantic findings are appended at
the end.

**Note on noise ignored throughout:** the `dom-6` "resource should have
narrative" warning is a best-practice recommendation, not a defect — omitted
from findings. The `-tx n/a` "unable to validate code…" warnings are just the
skipped terminology check — also ignored.

---

## Summary table

| # | Operation | LOINC | SNOMED | Key issue |
|---|---|---|---|---|
| 1 | `$lookup` valid | PASS | **FAIL** | S1: boolean property → empty `part:[]` (SNOMED only) |
| 2 | `$lookup` invalid | **FAIL** | **FAIL** | S2: HTTP status in issue-type coding |
| 3 | CodeSystem read | PASS\* | PASS | S6: LOINC `content=complete` but no concepts |
| 4 | `$subsumes` subsumes | — | PASS\* | B7: returns invalid outcome `"subsumed"` |
| 5 | `$subsumes` equivalent | PASS | PASS | correct |
| 6 | `$find-code` no system | **FAIL** | **FAIL** | S3: Codings wrapped as Bundle resources (80 errors) |
| 7 | `$find-code` with system | **FAIL** | **FAIL** | B1 SQL bug + B5 SQL leak + S2 |
| 8 | `$expand` | **FAIL** | **FAIL** | S4: `contains` entries missing `system` |
| 9 | `$validate-code` in set | PASS | PASS | correct |
| 10 | `$validate-code` not in set | **FAIL** | **FAIL** | B4 (404 not false) + S2 |

`PASS*` = 0 errors but a substantive warning/behaviour worth noting.

---

## 1. `$lookup`

### LOINC
- **Conformance:** PASS — 0 errors, 0 warnings, 16 notes.
- **Findings:**
  - The 16 notes are the "parameter has no value" info notes on each `property`.
    These are **benign** — `$lookup` legitimately uses `part`-style property
    parameters, not `value`. Not a defect.
  - All properties carry a proper `part` (code + value). Clean.
- **Expected vs output:** Match. `result`/`display`/`property[]` well-formed.
- **Changes:** None.

### SNOMED
- **Conformance:** FAIL — 2 errors, 3 warnings, 7 notes.
- **Findings:**
  - **S1** — the `active` property is emitted as `{"name":"property","part":[]}`
    (empty array). Errors: "Array cannot be empty" + `inv-1` ("a parameter must
    have one and only one of value/resource/part").
  - Cause: the `active` value is a **boolean**; the property→parameter mapper
    has no `valueBoolean` branch, so it produces an empty `part`. (LOINC has no
    boolean properties, so it never hits this.)
  - The 7 notes are the same benign part-style notes as LOINC.
- **Expected vs output:**
  - Expected: `{"name":"property","part":[{"name":"code","valueCode":"active"},{"name":"value","valueBoolean":true}]}`
  - Got: `{"name":"property","part":[]}`
- **Changes:** Add a `valueBoolean` branch to `codeSystemConceptPropertyToParameter`
  (`data_mapping.bal`) so boolean properties emit a proper `code`+`value` part.
- **Semantic result:** same 2 errors. The codes that the validator *can* check —
  the concept id and the designation `use` codings (`900000000000003001` /
  `900000000000013009`, incl. their displays "Fully specified name"/"Synonym") —
  all validated cleanly against SNOMED International.
  - **Not checked:** the top-level `display` valueString (`"Diabetes mellitus"`)
    is a bare parameter with no code bound to it, so the validator did **not**
    verify it against `73211009`. Verifying the concept-display / property /
    definition mappings still requires a reference-server comparison (see note
    at end).

---

## 2. `$lookup` — invalid code

### LOINC
- **Conformance:** FAIL — 1 error, 1 warning.
- **Findings:**
  - **S2** — `OperationOutcome.issue.details.coding.code = "404"` under system
    `http://hl7.org/fhir/issue-type`. "404" is **not** a valid code in that
    system → validator error "Unknown code '404'".
  - `issue.code = "required"` is a valid code but semantically wrong for
    "not found".
- **Expected vs output:**
  - Expected: an `OperationOutcome` whose `details.coding` uses a real issue-type
    code, e.g. `not-found`; HTTP status conveyed separately (not as an issue-type
    code).
  - Got: `details.coding.code = "404"`, `issue.code = "required"`.
- **Changes:** Map HTTP status → valid issue-type code (`not-found` for 404,
  `exception` for 500). Don't put HTTP status codes under the issue-type system.
- **Behaviour note:** returning an error for an unknown code is *acceptable* for
  `$lookup` — only the OperationOutcome shape is wrong.

### SNOMED
- **Conformance:** FAIL — 1 error, 1 warning. **Identical to LOINC (S2).**
- Same finding, expected/output, and fix as above. Confirms S2 is in shared
  error-response code, not per-system.

---

## 3. CodeSystem read

### LOINC
- **Conformance:** PASS\* — 0 errors, 2 warnings.
- **Findings:**
  - **S6** — warning: "When a CodeSystem has content = 'complete', it doesn't
    make sense for there to be no concepts defined." LOINC's stored CodeSystem
    says `content: "complete"` but carries no inline concepts (they're in the
    concepts table).
- **Expected vs output:**
  - Expected: `content` reflecting that concepts live elsewhere (`fragment` or
    `not-present`).
  - Got: `content: "complete"` with no concepts.
- **Changes:** Reconsider LOINC's `content` value — `complete` is misleading when
  concepts aren't inline. (Relates to the "store whole CodeSystem as BYTEA"
  review item.)

### SNOMED
- **Conformance:** PASS — 0 errors, 1 warning (only the benign narrative one).
- **Findings:** None. `content: "fragment"` is correct and **avoids** the
  warning LOINC gets — the fragment design choice is validated here.
- **Changes:** None.

---

## 4. `$subsumes` — subsumes case (SNOMED only)

### SNOMED
- **Conformance:** Structural PASS\* (0 errors) · Semantic PASS\* (0 errors).
- **Findings:**
  - **B7 (important)** — for `codeA=138875005` (root) subsuming
    `codeB=73211009` (diabetes), the response is
    `{"name":"outcome","valueCode":"subsumed"}`.
  - `"subsumed"` is **not** a valid FHIR `ConceptSubsumptionOutcome`. The only
    valid codes are `equivalent`, `subsumes`, `subsumed-by`, `not-subsumed`.
- **Semantic result:** it passed **even with terminology on** — the validator
  cannot catch this. `outcome` is a bare `valueCode` with no system/binding in
  the `Parameters` structure; the "must be one of the four" rule lives in the
  `$subsumes` OperationDefinition, which the validator doesn't apply to a
  response. (By contrast the `404`/`500` errors *are* caught, because they sit in
  a `coding` that names its own system.) **B7 was found by manual inspection
  only** — a real blind spot of the tool.
- **Expected vs output:**
  - Expected: `"subsumes"` (A is an ancestor of B).
  - Got: `"subsumed"` (invalid code).
- **Changes:** Fix the outcome mapping to emit the valid codes — `"subsumes"`
  when A subsumes B, `"subsumed-by"` when A is subsumed by B.

### LOINC
- n/a — LOINC has no is-a hierarchy loaded.

---

## 5. `$subsumes` — equivalent case

### LOINC
- **Conformance:** PASS — 0 errors, 0 warnings, 1 note.
- **Findings:** `outcome = "equivalent"` for `codeA = codeB`. Valid code, correct
  result.
- **Changes:** None.

### SNOMED
- **Conformance:** PASS — 0 errors, 0 warnings, 1 note.
- **Findings:** `outcome = "equivalent"`. Correct.
- **Changes:** None.
- **Contrast with #4:** the equivalent path emits a valid code, but the subsumes
  path emits the invalid `"subsumed"` — so B7 is isolated to the subsumes/
  subsumed-by mapping.

---

## 6. `$find-code` — no system

### LOINC
- **Conformance:** FAIL — 80 errors, 22 warnings.
- **Findings:**
  - **S3** — each `Bundle.entry.resource` is a bare **Coding**
    (`{system, code, display}`), not a FHIR Resource. Errors per entry:
    - Fatal: "Unable to find resourceType property"
    - "Resource requires an id"
    - `bdl-5`: "must be a resource…"
    - "each entry must have a fullUrl"
  - Warnings: "Search results must have ids", "SearchSet should have a self
    link", "should have search modes on entries".
  - **B6** — the search returned **SNOMED** rows for a LOINC-intended `glucose`
    query (see behavioural section): no `system` scoping + case-sensitive match.
- **Expected vs output:**
  - Expected: a searchset Bundle whose entries are valid Resources (each with
    `resourceType`, `id`, `fullUrl`, `search.mode`).
  - Got: entries wrapping raw Codings.
- **Changes:** Redesign the `$find-code` result shape — wrap each hit in a real
  Resource (or return a `Parameters`/`ValueSet` expansion instead of a Bundle of
  Codings); add `fullUrl`, `search.mode`, ids, and a self link.

### SNOMED
- **Conformance:** FAIL — 80 errors, 22 warnings. **Same S3 as LOINC.**
- Same findings, expected/output, and fix. Confirms S3 affects `$find-code`
  regardless of system.

---

## 7. `$find-code` — with system

### LOINC
- **Conformance:** FAIL — 1 error, 1 warning.
- **Findings:**
  - **B1** — 500 error: the SQL references `c."url"`, but the concepts table is
    aliased `"Concept"` (not `c`) → `missing FROM-clause entry for table "c"`.
    The `system` filter is broken.
  - **B5 (security)** — the full raw SQL and schema are returned in
    `details.text` to the client.
  - **S2** — the OperationOutcome uses `code = "500"` in issue-type coding
    (same invalid-code problem as #2).
- **Expected vs output:**
  - Expected: a Bundle filtered to `http://loinc.org`.
  - Got: 500 OperationOutcome leaking SQL.
- **Changes:** Fix the query to join/filter on the codesystems `url` via the
  correct alias; return a generic error message (no SQL); use a valid issue-type
  code.

### SNOMED
- **Conformance:** FAIL — 1 error, 1 warning. **Identical (B1 + B5 + S2).**
- Confirms B1/B5 affect both systems — it's shared `$find-code` code.

---

## 8. `$expand`

### LOINC
- **Conformance:** FAIL — 1 error, 3 warnings, 1 note.
- **Findings:**
  - **S4** — `expansion.contains[0]` has `code` + `display` but no `system` →
    `vsd-10` "Must have a system if a code is present".
  - **S5 (minor)** — warning: expansion has no `parameters`; note: expansion has
    no `identifier` (both best-practice).
  - Warning: references CodeSystem `http://loinc.org` with status `not-present`
    (tx-view; low priority).
- **Expected vs output:**
  - Expected: each `contains` entry carries `system` (+ ideally `version`).
  - Got: `{"code":"100011-6","display":"…"}` — no `system`.
- **Changes:** Add `system` (and version) to every `expansion.contains` entry;
  record expansion `parameters` and an `identifier`.

### SNOMED
- **Conformance:** FAIL — 2 errors, 3 warnings, 1 note.
- **Findings:** Same **S4** — both contained concepts (73211009, 44054006) miss
  `system` → 2 `vsd-10` errors. Same S5 minor items.
- **Expected vs output:** same as LOINC.
- **Changes:** same as LOINC.
- **Semantic result (both systems):** the semantic pass added one warning — "the
  expansion is missing … codes … that are in the expansion using default
  parameters" (SNOMED: 73211009, 44054006; LOINC: 100011-6). The tx server
  expanded the value set itself and got exactly the codes we listed, but because
  our `contains` entries omit `system` (S4) it can't match them. This
  **confirms** the membership is correct and only the structure (missing
  `system`) is wrong.

---

## 9. `$validate-code` — in set

### LOINC
- **Conformance:** PASS — 0 errors, 0 warnings, 1 note.
- **Findings:** `result: true` + `display`. Correct.
- **Changes:** None.

### SNOMED
- **Conformance:** PASS — 0 errors, 0 warnings, 1 note.
- **Findings:** `result: true` + `display` + `definition`. Correct.
- **Changes:** None.

---

## 10. `$validate-code` — not in set

### LOINC
- **Conformance:** FAIL — 1 error, 1 warning.
- **Findings:**
  - **B4 (behavioural)** — returns `404 OperationOutcome "Concept not found"`
    instead of `Parameters` with `result: false`.
  - **S2** — the 404 OperationOutcome is itself malformed (invalid issue-type
    code).
- **Expected vs output:**
  - Expected: `{"parameter":[{"name":"result","valueBoolean":false}, …]}`
  - Got: 404 OperationOutcome.
- **Changes:** For a code that isn't a member, return `Parameters` with
  `result: false` (and a `message`), not an error.

### SNOMED
- **Conformance:** FAIL — 1 error, 1 warning. **Same B4 + S2 as LOINC.**
- Same expected/output and fix.

---

## Findings register (structural pass)

| ID | Type | Severity | Summary | Scope |
|---|---|---|---|---|
| S1 | structural | high | boolean property → empty `part:[]` in `$lookup` | SNOMED (shared code) |
| S2 | structural | high | HTTP status codes placed in issue-type `coding.code` on all error responses | both |
| S3 | structural | high | `$find-code` wraps bare Codings as Bundle resources (no resourceType/id/fullUrl) | both |
| S4 | structural | med | `$expand` `contains` entries omit `system` (`vsd-10`) | both |
| S5 | structural | low | `$expand` expansion lacks `parameters` + `identifier` | both |
| S6 | structural | low | LOINC CodeSystem `content=complete` but no inline concepts | LOINC |
| B7 | behavioural/semantic | high | `$subsumes` returns invalid outcome `"subsumed"` (should be `"subsumes"`) | SNOMED |

(B1 SQL `c.url`, B4 validate-code 404, B5 SQL leak, B6 find-code scope/case are
in the behavioural section — carried over and now confirmed on both systems.)

---

## Semantic pass — method and overall result

Re-ran every file with terminology on — SNOMED with `-sct intl` (International),
LOINC against `tx.fhir.org` — to check the **codes** and **displays** on top of
structure. Operation-specific semantic results are folded into each section
above (`$lookup`, `$subsumes`, `$expand`). Overall:

- **Every structural error reproduced identically** — nothing was hidden by the
  `-tx n/a` mode.
- **Positive:** all SNOMED codes the validator can check (concept ids +
  designation `use` codings, including their displays) resolved against SNOMED
  International. So those codes are real and those codings are correct.
- **Not verified by the tool:** the top-level `display`/`definition` and the
  `property` values are bare parameter values with no inline system/binding, so
  the validator can't check whether they map from the right source column. That
  needs a **reference-server comparison** (Ontoserver / tx.fhir.org) — a separate
  step. This is the same blind spot as B7 (bare `valueCode`/`valueString`).
- **Only one operation gained a new signal:** `$expand`'s "missing codes"
  warning, which corroborates S4 (see §8).
- **The tool could not catch B7** (`$subsumes` `"subsumed"`) even semantically —
  see §4. Manual inspection remains necessary.

---

# Behavioural findings

These are **wrong behaviour** the validator can't judge — the response may be
well-formed FHIR (or a well-formed error) but does the wrong thing. Found by
comparing actual responses to the spec and to the LOINC reference.

## B1 — `$find-code` with `system` filter → SQL error
- **Operations:** `$find-code?system=` (both SNOMED and LOINC).
- **Evidence:** 500 response; `details.text` contains the raw SQL ending in
  `… WHERE "display" ~ '.*…*' AND c."url" = ? …` → `ERROR: missing FROM-clause
  entry for table "c"`.
- **Cause:** the concepts table is aliased `"Concept"` and codesystems
  `"codeSystem"`, but the filter references alias `c`, which doesn't exist.
- **Fix:** filter on the codesystems `url` via the correct join alias.

## B2 — POST `$expand` ignores query parameters
- **Operation:** `POST /ValueSet/$expand?url=…&filter=…`.
- **Evidence:** the ValueSet isn't resolved; the handler reads `url`/`filter`
  from search params, which aren't populated on a POST operation.
- **Fix:** read `url`/`filter` from the query string on POST too, or require them
  in the `Parameters` body. (GET-by-id `$expand` works.)

## B4 — `$validate-code` (not in set) returns 404 instead of `result: false`
- **Operations:** `$validate-code` not-in-set (both systems).
- **Evidence:** `404 OperationOutcome "Concept not found"` instead of
  `Parameters` with `result: false`. (Also malformed per S2.)
- **Fix:** return `Parameters` with `result: false` (+ a `message`) for a
  non-member code.

## B5 — error responses leak raw SQL and schema (security)
- **Operations:** any path that surfaces a DB exception (seen in `$find-code`
  with system).
- **Evidence:** `details.text` returns the full SQL SELECT with all column and
  table names.
- **Fix:** return a generic error message; log the SQL server-side only. **Flag
  to mentor — information disclosure.**

## B6 — `$find-code` is case-sensitive and can't scope by system
- **Operations:** `$find-code` (both systems).
- **Evidence:** `filter=glucose` returned only SNOMED rows — LOINC's `"Glucose"`
  (capital G) didn't match the case-sensitive Postgres `~`. And with the
  `system` filter broken (B1), there's no way to scope to one code system.
- **Fix:** case-insensitive match (`~*`); make the `system` filter work (B1).

## B7 — `$subsumes` returns invalid outcome code (see §4)
- Carried here for completeness. `"subsumed"` is not a valid
  `ConceptSubsumptionOutcome`; should be `"subsumes"`. Not tool-catchable.

---

# Master findings register

| ID | Type | Severity | Summary | Scope |
|---|---|---|---|---|
| S1 | structural | high | `$lookup` boolean property → empty `part:[]` | SNOMED (shared code) |
| S2 | structural | high | HTTP status in issue-type `coding.code` on all error responses | both |
| S3 | structural | high | `$find-code` wraps bare Codings as Bundle resources | both |
| S4 | structural | med | `$expand` `contains` entries omit `system` | both |
| S5 | structural | low | `$expand` lacks `parameters` + `identifier` | both |
| S6 | structural | low | LOINC CodeSystem `content=complete` but no concepts | LOINC |
| B1 | behavioural | high | `$find-code?system=` SQL error (`c.url`) | both |
| B2 | behavioural | med | POST `$expand` ignores query params | both |
| B4 | behavioural | high | `$validate-code` not-in returns 404, not `result:false` | both |
| B5 | security | high | error responses leak raw SQL/schema | all error paths |
| B6 | behavioural | med | `$find-code` case-sensitive + can't scope by system | both |
| B7 | behavioural | high | `$subsumes` invalid outcome `"subsumed"` (tool-blind) | SNOMED |

---

# Mapping verification (reference-server comparison)

Third verification layer — answers "are we mapping the **right source column to
the right FHIR field**?", which neither validator pass can judge. Method:
`$lookup` the same code on a reference server and diff field-by-field.

- SNOMED `73211009` — ours vs **Ontoserver** (`r4.ontoserver.csiro.au`).
- LOINC `100011-6` — ours vs **tx.fhir.org**.

> **Caveat (SNOMED):** Ontoserver resolved `73211009` against the SNOMED
> **Australian extension** (`…/20260630`), not International `20260401`. So
> display/definition differences are partly edition artefacts, not our bugs. The
> property/structure comparison still holds.

## SNOMED — ours vs Ontoserver

| Field | Ours | Reference | Assessment |
|---|---|---|---|
| `display` | "Diabetes mellitus" | "Diabetes" | inconclusive — different edition |
| `definition` | "Diabetes mellitus (disorder)" (FSN fallback) | (none) | **M-def**: we emit FSN-as-definition; reference emits none |
| active status | `active` → empty `part:[]` (S1) | `inactive` = false (boolean) | **M1**: wrong property name + form |
| definition status | `definitionStatusId` = "900000000000074008" | `sufficientlyDefined` = false (boolean) | **M1**: wrong property name + form |
| `moduleId` | valueString | valueCode | **M5**: wrong type (should be code) |
| `effectiveTime` | "20020131" | "20020131" | match |
| hierarchy | (none) | `parent`/`child` properties | **M3**: not emitted |
| designations | FSN + 2 synonyms | + `preferredForLanguage` marks | **M4**: no PT marking (Language Refset) |

## LOINC — ours vs tx.fhir.org

| Field | Ours | Reference | Assessment |
|---|---|---|---|
| `display` | "No injury related to an electrical source" | same | **match — `LONG_COMMON_NAME → display` verified ✓** |
| axis props (PROPERTY, TIME_ASPCT, SYSTEM, SCALE_TYP, CLASS) | display strings ("Find", "Pt", …) as `valueString` | LOINC Part codes (`LP6813-2`, …) as `valueCode` | **M2**: wrong value form (strings, not Part codes) |
| `COMPONENT` | (missing) | `LP430730-4` | **M2**: not emitted at all |
| active status | `STATUS` = "ACTIVE" only | + `inactive` = false (boolean) | **M1**: missing standard `inactive` |
| designations | (none) | preferredForLanguage + LONG_COMMON_NAME | **M4**: no designations for LOINC |
| raw CSV cols (VersionLastChanged, CHNG_TYPE, COMMON_TEST_RANK, …) | emitted as properties | not surfaced | **M6**: raw source columns dumped |
| ORDER_OBS, UNITSREQUIRED, STATUS value, RELATEDNAMES2 | present | present | match |

## Mapping findings register

| ID | Severity | Summary | Scope |
|---|---|---|---|
| M1 | high | Uses source status/def-status fields (`active`, `definitionStatusId`, `STATUS`) instead of the FHIR-standard properties (`inactive`, `sufficientlyDefined` booleans) | both |
| M2 | high | LOINC axis properties emitted as display strings, not LOINC Part codes; `COMPONENT` missing | LOINC |
| M3 | med | Hierarchy `parent`/`child` properties not emitted (data exists in closure) | SNOMED (LOINC n/a) |
| M4 | med | Designations: none for LOINC; SNOMED has no `preferredForLanguage` marking (Language Refset) | both |
| M5 | low | Coded property values typed as `valueString` instead of `valueCode`/`valueBoolean` | both |
| M6 | low | Raw source columns dumped as properties instead of a curated set | LOINC |
| M-def | low | SNOMED `definition` populated from FSN fallback where reference emits none | SNOMED |

## What this verified (positives)

- **LOINC `display` mapping is correct** (`LONG_COMMON_NAME → display`, exact match).
- SNOMED `moduleId` and `effectiveTime` **values** match (types aside).
- Several LOINC properties (ORDER_OBS, UNITSREQUIRED, STATUS, RELATEDNAMES2) match.

## Method caveats
- One reference concept per system is enough to check the *logic* (same for all
  concepts); spot-check 1–2 more if time allows.
- SNOMED display/definition comparison is confounded by Ontoserver's edition —
  re-run forcing International, or compare against `tx.fhir.org` SNOMED, for a
  clean display check.
- Reference servers are exhaustive; a *missing* property on our side is a gap,
  a *wrong-valued* one is a defect.
