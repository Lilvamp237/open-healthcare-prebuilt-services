# FHIR Conformance Audit — SNOMED CT vs LOINC

A structured conformance pass over every terminology operation, run against
**both** code systems. Structural compliance is checked with HL7's FHIR
validator; behavioural correctness is checked by comparing against the spec and
against the existing LOINC implementation (the in-house reference).

- Base URL: `http://localhost:9090/fhir/r4`
- Validator: `validator_cli.jar`, always `-version 4.0.1 -tx n/a` (structural
  only — same flags every run so LOINC and SNOMED are comparable)
- SNOMED system: `http://snomed.info/sct`
- LOINC system: `http://loinc.org`

### Reference values

| | SNOMED | LOINC |
|---|---|---|
| CodeSystem id | `snomed-ct` | `loinc` |
| Valid code | `73211009` (Diabetes mellitus) | `100011-6` |
| Invalid code | `99999999` | `00000-0` |
| Parent / child (subsumes) | `138875005` ⊃ `73211009` | n/a (no hierarchy loaded) |
| Example ValueSet id | `snomed-diabetes-example` | `loinc-example` (create below) |

---

## Step 0 — one-time setup: create both example ValueSets

**SNOMED ValueSet** (if not already created):
```
curl -X POST "http://localhost:9090/fhir/r4/ValueSet" -H "Content-Type: application/fhir+json" -d "{\"resourceType\":\"ValueSet\",\"id\":\"snomed-diabetes-example\",\"url\":\"http://example.org/fhir/ValueSet/snomed-diabetes-example\",\"version\":\"1.0.0\",\"name\":\"SnomedDiabetesExample\",\"title\":\"SNOMED diabetes example\",\"status\":\"active\",\"compose\":{\"include\":[{\"system\":\"http://snomed.info/sct\",\"concept\":[{\"code\":\"73211009\"},{\"code\":\"44054006\"}]}]}}"
```

**LOINC ValueSet**:
```
curl -X POST "http://localhost:9090/fhir/r4/ValueSet" -H "Content-Type: application/fhir+json" -d "{\"resourceType\":\"ValueSet\",\"id\":\"loinc-example\",\"url\":\"http://example.org/fhir/ValueSet/loinc-example\",\"version\":\"1.0.0\",\"name\":\"LoincExample\",\"title\":\"LOINC example\",\"status\":\"active\",\"compose\":{\"include\":[{\"system\":\"http://loinc.org\",\"concept\":[{\"code\":\"100011-6\"}]}]}}"
```
Both should return **201 Created**.

---

## Step 1 — capture every response to a file

Run these from `C:\` (or anywhere). They save to Downloads. `$` in `$lookup`
etc. works in cmd.exe as-is; if you use PowerShell, wrap each URL in single
quotes.

### SNOMED
```
curl "http://localhost:9090/fhir/r4/CodeSystem/$lookup?system=http://snomed.info/sct&code=73211009" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-lookup-valid.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/$lookup?system=http://snomed.info/sct&code=99999999" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-lookup-invalid.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/snomed-ct" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-codesystem.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/$subsumes?system=http://snomed.info/sct&codeA=138875005&codeB=73211009" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-subsumes-subsumes.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/$subsumes?system=http://snomed.info/sct&codeA=73211009&codeB=73211009" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-subsumes-equivalent.json"
curl "http://localhost:9090/fhir/r4/$find-code?filter=diabetes&property=display" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-findcode-nosystem.json"
curl "http://localhost:9090/fhir/r4/$find-code?system=http://snomed.info/sct&filter=diabetes&property=display" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-findcode-withsystem.json"
curl "http://localhost:9090/fhir/r4/ValueSet/snomed-diabetes-example/$expand" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-expand.json"
curl "http://localhost:9090/fhir/r4/ValueSet/snomed-diabetes-example/$validate-code?system=http://snomed.info/sct&code=73211009" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-validate-in.json"
curl "http://localhost:9090/fhir/r4/ValueSet/snomed-diabetes-example/$validate-code?system=http://snomed.info/sct&code=195967001" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\sn-validate-notin.json"
```

### LOINC
```
curl "http://localhost:9090/fhir/r4/CodeSystem/$lookup?system=http://loinc.org&code=100011-6" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-lookup-valid.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/$lookup?system=http://loinc.org&code=00000-0" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-lookup-invalid.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/loinc" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-codesystem.json"
curl "http://localhost:9090/fhir/r4/CodeSystem/$subsumes?system=http://loinc.org&codeA=100011-6&codeB=100011-6" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-subsumes-equivalent.json"
curl "http://localhost:9090/fhir/r4/$find-code?filter=glucose&property=display" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-findcode-nosystem.json"
curl "http://localhost:9090/fhir/r4/ValueSet/loinc-example/$expand" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-expand.json"
curl "http://localhost:9090/fhir/r4/ValueSet/loinc-example/$validate-code?system=http://loinc.org&code=100011-6" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-validate-in.json"
curl "http://localhost:9090/fhir/r4/ValueSet/loinc-example/$validate-code?system=http://loinc.org&code=00000-0" -H "Accept: application/fhir+json" -o "C:\Users\Sumudu Ratnayake\Downloads\lo-validate-notin.json"
```

> Before validating each file, open it once to confirm it's a real response and
> not an error page. A file that starts with `{"resourceType":"OperationOutcome"`
> is the server returning an error — that's itself a finding, record it.

---

## Step 2 — validate every file

Run the validator on each saved file with the same flags:
```
java -jar validator_cli.jar "C:\Users\Sumudu Ratnayake\Downloads\<file>.json" -version 4.0.1 -tx n/a
```
Record the summary line (`*SUCCESS*` / `*FAILURE*`, error count) and any errors.

---

## Step 3 — the audit grid (fill this in)

Legend: **PASS** = 0 errors · **WARN** = warnings/notes only · **FAIL** = ≥1 error · **ERR-RESP** = server returned OperationOutcome

### Structural conformance (validator verdict)

Each code system gets its own **result** and **errors/notes** column.

- **result** = one token: `PASS` (0 errors) · `FAIL` (≥1 error) · `PASS*`
  (0 errors but a substantive info note flagged) · `ERR-RESP` (server returned
  an OperationOutcome).
- **errors/notes** = a short summary of the *errors* only, plus any *substantive*
  info note (e.g. "value-less param"). Ignore `-tx n/a` warnings and repeated
  boilerplate notes.

Row 1 is filled in as a worked example — copy its pattern for the rest.

| # | Operation | Case | SNOMED result | SNOMED errors/notes | LOINC result | LOINC errors/notes |
|---|---|---|---|---|---|---|
| 1 | `$lookup` | valid code | **FAIL** | `part:[]` empty; `inv-1` (param needs value/resource/part) — defect S1 | **PASS\*** | 0 errors, but value-less `property`/`designation` params flagged (info) — same pattern, defect S1 |
| 2 | `$lookup` | invalid code | | | | |
| 3 | CodeSystem read | by id | | | | |
| 4 | `$subsumes` | subsumes | | | — | LOINC n/a (no hierarchy) |
| 5 | `$subsumes` | equivalent | | | | |
| 6 | `$find-code` | no system | | | | |
| 7 | `$find-code` | with system | | | — | |
| 8 | `$expand` | ValueSet | | | | |
| 9 | `$validate-code` | in set | | | | |
| 10 | `$validate-code` | not in set | | | | |

File names for reference (Step 1): `sn-…` / `lo-…` per operation, e.g.
`sn-lookup-valid.json`, `lo-lookup-valid.json`.

### Behavioural conformance (validator can't judge — you compare to expected)

The validator only checks *shape*. These checks are about whether the operation
does the *right thing*. Compare each response's content to the "expected"
column.

| # | Operation | Input | Expected (per spec / LOINC reference) | SNOMED actual | LOINC actual | Divergence? |
|---|---|---|---|---|---|---|
| B1 | `$lookup` valid | known code | `display` = concept name; `Parameters` with name/display | | | |
| B2 | `$lookup` invalid | bad code | error / OperationOutcome, not a 200 with empty result | | | |
| B3 | `$subsumes` | root vs child | `outcome` = `subsumes` | | n/a | |
| B4 | `$subsumes` | same code | `outcome` = `equivalent` | | | |
| B5 | `$find-code` | with `system=` | filtered results for that system | | | **known: SNOMED errors on c.url** |
| B6 | `$expand` | ValueSet | `expansion.contains` lists the member codes w/ display | | | |
| B7 | `$validate-code` in | member code | `result` = true | | | |
| B8 | `$validate-code` not-in | non-member | `result` = false | | | |

---

## Step 4 — findings log

Number each finding. Separate **structural** (validator-caught, objective) from
**behavioural** (wrong result, needs judgement). Link to an issue or mark NEW.

### Structural findings

| ID | Operation(s) affected | Symptom | Root cause | Scope (SNOMED / LOINC / both) | Issue # |
|---|---|---|---|---|---|
| S1 | `$lookup` | `property` emitted as `{"name":"property","part":[]}` → `inv-1` + empty-array errors | `codeSystemConceptPropertyToParameter` has no `valueBoolean` branch; `part` assigned unconditionally | both (SNOMED errors, LOINC warns) | _fill_ |
| S2 | | | | | |

### Behavioural findings

| ID | Operation | Expected | Actual | Root cause | Scope | Issue # |
|---|---|---|---|---|---|---|
| B-1 | `$find-code?system=` | filter to that system | request errors | `searchConcept` filters on `c.url`, which isn't a column on `concepts` | both | _fill_ |
| B-2 | POST `$expand?url=…` | expands the ValueSet | can't resolve | url/filter read from query params, not honoured on POST | both | _fill_ |
| B-3 | | | | | | |

---

## Notes on LOINC-specific gaps (expected, not bugs)

- **`$subsumes` on LOINC**: LOINC has no is-a hierarchy loaded (no closure), so
  subsumption other than `equivalent` will likely return `not-subsumed` or
  not-found. That's expected — record it as an expected divergence, not a defect.
- **LOINC ValueSet**: created above with a single code. `$validate-code`
  not-in-set uses a code that isn't a member.

## How to read the results

- **SNOMED FAIL + LOINC PASS, same operation** → the defect is triggered by
  something SNOMED has that LOINC doesn't (e.g. boolean properties). Strengthens
  the finding — you can point at the exact difference.
- **Both FAIL** → shared defect in common code. Higher priority; one fix helps
  both.
- **Both PASS** → confirmed conformant. Positive evidence, worth recording.
- **Structural PASS but behavioural divergence** → valid FHIR, wrong behaviour.
  The validator won't catch these — only the behavioural grid does.
