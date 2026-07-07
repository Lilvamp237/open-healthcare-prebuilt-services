# SNOMED CT → FHIR — POC Testing Guide

This document is a step-by-step test pass for the SNOMED CT proof-of-concept. It
covers every FHIR terminology operation the service exposes, with a ready-to-run
request and an expected result for each. Work through it top to bottom and record
the outcome in the results table at the end.

---

## Prerequisites

1. **Service running** and the **SNOMED release already imported** (via
   `POST /$upload`). The import must have finished — look for the
   `SNOMED import complete: ...` line in the server log.
2. **Base URL:** `http://localhost:9090/fhir/r4` (adjust the port to your
   instance). This document abbreviates it as `{BASE}`.
3. **A REST client:** Postman or curl. Examples below use curl; the same
   method / URL / headers / body work in Postman.
4. **Reference codes used throughout** (standard SNOMED International):

   | Code | Meaning |
   |---|---|
   | 138875005 | SNOMED CT Concept (the hierarchy root) |
   | 73211009 | Diabetes mellitus |
   | 44054006 | Diabetes mellitus type 2 |
   | 195967001 | Asthma (used as a code *not* in the sample value set) |

---

## Operations NOT tested (and why)

- **CodeSystem `$validate-code`** — not implemented in this service (only
  ValueSet `$validate-code` exists). Testing it returns 404.
- **ConceptMap / `$translate`** — out of POC scope; stubbed.

---

## Group A — Service metadata

### A1 — Capability statement
**Purpose:** Confirm the service is up and advertises its operations.
```
curl "{BASE}/metadata"
```
**Expected:** A `CapabilityStatement` resource listing CodeSystem and ValueSet
resources with their operations. HTTP 200.

### A2 — Terminology capabilities
**Purpose:** Confirm SNOMED is advertised as a supported code system.
```
curl "{BASE}/metadata?mode=terminology"
```
**Expected:** A `TerminologyCapabilities` resource whose `codeSystem` list
includes `http://snomed.info/sct`. HTTP 200.

---

## Group B — CodeSystem read & search

### B1 — Read the SNOMED CodeSystem
**Purpose:** Confirm the metadata row was stored correctly.
```
curl "{BASE}/CodeSystem/snomed-ct"
```
**Expected:** A `CodeSystem` with `title: "SNOMED Clinical Terms"`,
`url: "http://snomed.info/sct"`, `content: "fragment"`, and **no** inline
`concept` array. HTTP 200.

### B2 — Search CodeSystems by URL
**Purpose:** Confirm search returns the SNOMED entry.
```
curl "{BASE}/CodeSystem?url=http://snomed.info/sct"
```
**Expected:** A searchset `Bundle` containing the SNOMED `CodeSystem`. HTTP 200.

---

## Group C — CodeSystem $lookup

### C1 — Lookup by code (GET)
**Purpose:** Confirm a concept resolves to its display, designations, and
properties.
```
curl "{BASE}/CodeSystem/\$lookup?system=http://snomed.info/sct&code=73211009"
```
**Expected:** A `Parameters` resource with `display: "Diabetes mellitus"`, one
or more `designation` entries (FSN + synonyms), and `property` entries
(`moduleId`, `definitionStatusId`, `effectiveTime`). HTTP 200.

> Note: the `active` property currently renders as an empty `part` — a known
> pre-existing display bug unrelated to SNOMED; the value is stored correctly.

### C2 — Lookup by code (POST)
**Purpose:** Same as C1 via a request body.
```
curl -X POST "{BASE}/CodeSystem/\$lookup" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Parameters",
    "parameter": [
      {"name": "coding", "valueCoding": {"system": "http://snomed.info/sct", "code": "73211009"}}
    ]
  }'
```
**Expected:** Same result as C1. HTTP 200.

---

## Group D — CodeSystem $subsumes

This is the operation the parent-linking pass enables.

### D1 — Root subsumes a concept (reliable)
**Purpose:** Confirm hierarchy traversal works. Every concept chains up to the
root, so this should always pass.
```
curl "{BASE}/CodeSystem/\$subsumes?system=http://snomed.info/sct&codeA=138875005&codeB=73211009"
```
**Expected:** `Parameters` with `outcome: "subsumes"` (A is an ancestor of B).
HTTP 200.

### D2 — Equivalent codes
**Purpose:** Confirm identical codes report equivalence.
```
curl "{BASE}/CodeSystem/\$subsumes?system=http://snomed.info/sct&codeA=73211009&codeB=73211009"
```
**Expected:** `outcome: "equivalent"`. HTTP 200.

### D3 — Parent subsumes child (POST)
**Purpose:** Test a specific parent/child pair via a body.
```
curl -X POST "{BASE}/CodeSystem/\$subsumes" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Parameters",
    "parameter": [
      {"name": "system", "valueUri": "http://snomed.info/sct"},
      {"name": "codingA", "valueCoding": {"system": "http://snomed.info/sct", "code": "73211009"}},
      {"name": "codingB", "valueCoding": {"system": "http://snomed.info/sct", "code": "44054006"}}
    ]
  }'
```
**Expected:** `outcome: "subsumes"` **or** `"not-subsumed"`. See the limitation
note below — because the POC stores only one parent per concept, some valid
subsumptions can return `not-subsumed`. D1 is the guaranteed check.

---

## Group E — Find code

### E1 — Find concepts by display text (GET)
**Purpose:** Confirm concept text search works.
```
curl "{BASE}/\$find-code?system=http://snomed.info/sct&filter=diabetes&property=display&_count=10"
```
**Expected:** A searchset `Bundle` of `Coding` entries whose display contains
"diabetes". HTTP 200.

### E2 — Find concepts (POST)
```
curl -X POST "{BASE}/\$find-code" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Parameters",
    "parameter": [
      {"name": "system", "valueString": "http://snomed.info/sct"},
      {"name": "filter", "valueString": "diabetes"},
      {"name": "property", "valueString": "display"},
      {"name": "_count", "valueInteger": 10}
    ]
  }'
```
**Expected:** Same shape as E1. HTTP 200.

---

## Group F — ValueSet create, read, search

The import does not create any SNOMED value set, so we create a small
extensional one first, then exercise it.

### F1 — Create an extensional SNOMED ValueSet
**Purpose:** Store a value set that lists two SNOMED codes.
```
curl -X POST "{BASE}/ValueSet" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "ValueSet",
    "id": "snomed-diabetes-example",
    "url": "http://example.org/fhir/ValueSet/snomed-diabetes-example",
    "version": "1.0.0",
    "name": "SnomedDiabetesExample",
    "title": "SNOMED diabetes example",
    "status": "active",
    "compose": {
      "include": [
        {
          "system": "http://snomed.info/sct",
          "concept": [
            {"code": "73211009"},
            {"code": "44054006"}
          ]
        }
      ]
    }
  }'
```
**Expected:** HTTP 201 Created.

### F2 — Read the ValueSet by id
```
curl "{BASE}/ValueSet/snomed-diabetes-example"
```
**Expected:** The `ValueSet` resource. HTTP 200.

### F3 — Search ValueSets by URL
```
curl "{BASE}/ValueSet?url=http://example.org/fhir/ValueSet/snomed-diabetes-example"
```
**Expected:** A searchset `Bundle` containing the value set. HTTP 200.

---

## Group G — ValueSet $expand

### G1 — Expand by id
**Purpose:** Confirm the listed concepts come back with their SNOMED displays.
```
curl "{BASE}/ValueSet/snomed-diabetes-example/\$expand"
```
**Expected:** The `ValueSet` with an `expansion.contains` array of two entries
(codes 73211009 and 44054006) each with a `display`. HTTP 200.

### G2 — Expand by URL with a filter (POST)
**Purpose:** Confirm the display filter narrows the expansion.
```
curl -X POST "{BASE}/ValueSet/\$expand?url=http://example.org/fhir/ValueSet/snomed-diabetes-example&filter=type" \
  -H "Content-Type: application/fhir+json" \
  -d '{"resourceType": "Parameters"}'
```
**Expected:** An expansion containing only the concept whose display matches
"type" (44054006, "Diabetes mellitus type 2"). HTTP 200.

---

## Group H — ValueSet $validate-code

### H1 — Code that IS in the value set
```
curl "{BASE}/ValueSet/snomed-diabetes-example/\$validate-code?system=http://snomed.info/sct&code=73211009"
```
**Expected:** `Parameters` with `result: true`. HTTP 200.

### H2 — Code that is NOT in the value set
```
curl "{BASE}/ValueSet/snomed-diabetes-example/\$validate-code?system=http://snomed.info/sct&code=195967001"
```
**Expected:** `Parameters` with `result: false`. HTTP 200.

### H3 — Validate code (POST)
```
curl -X POST "{BASE}/ValueSet/\$validate-code" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Parameters",
    "parameter": [
      {"name": "valueSet", "resource": {
        "resourceType": "ValueSet",
        "url": "http://example.org/fhir/ValueSet/snomed-diabetes-example",
        "status": "active"
      }},
      {"name": "coding", "valueCoding": {"system": "http://snomed.info/sct", "code": "73211009"}}
    ]
  }'
```
**Expected:** `result: true`. HTTP 200.

---

## Group I — Batch validate

### I1 — Validate several codes in one request
**Purpose:** Confirm the batch endpoint validates each code against the value
set. Note: in this service the batch entry's `system` parameter holds the
**value set URL**, and `code` is the code to check.
```
curl -X POST "{BASE}/" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Bundle",
    "type": "batch",
    "entry": [
      {"request": {"method": "GET", "url": "ValueSet/$validate-code?system=http://example.org/fhir/ValueSet/snomed-diabetes-example&code=73211009"}},
      {"request": {"method": "GET", "url": "ValueSet/$validate-code?system=http://example.org/fhir/ValueSet/snomed-diabetes-example&code=195967001"}}
    ]
  }'
```
**Expected:** A batch-response `Bundle` with two `Parameters` entries — the first
`result: true`, the second `result: false`. HTTP 200.

---

## Known limitations that affect testing

| Behaviour | Effect on tests |
|---|---|
| One parent per concept (POC) | `$subsumes` follows a single parent chain. D1 (root over any concept) always works; arbitrary pairs (D3) may return `not-subsumed` even when a true is-a path exists through a different parent. |
| Active concepts only | `$lookup` / `$validate-code` on a retired (inactive) code returns not-found, not "inactive". |
| CodeSystem `$validate-code` not implemented | Endpoint returns 404 — excluded from this pass. |
| `active` property render | Shows as an empty `part` in `$lookup` output; the value is stored correctly (pre-existing bug, not SNOMED-specific). |

---

## Results table

Fill this in as you run each test.

| # | Operation | Expected | Result (pass/fail) | Notes |
|---|---|---|---|---|
| A1 | GET /metadata | 200, CapabilityStatement | | |
| A2 | GET /metadata?mode=terminology | 200, SNOMED listed | | |
| B1 | GET /CodeSystem/snomed-ct | title + content=fragment | | |
| B2 | GET /CodeSystem?url=… | Bundle with SNOMED | | |
| C1 | GET /CodeSystem/$lookup | display + designations | | |
| C2 | POST /CodeSystem/$lookup | same as C1 | | |
| D1 | $subsumes root→diabetes | subsumes | | |
| D2 | $subsumes equal codes | equivalent | | |
| D3 | POST $subsumes parent→child | subsumes / not-subsumed | | |
| E1 | GET /$find-code | Bundle of matches | | |
| E2 | POST /$find-code | Bundle of matches | | |
| F1 | POST /ValueSet | 201 Created | | |
| F2 | GET /ValueSet/{id} | the ValueSet | | |
| F3 | GET /ValueSet?url=… | Bundle | | |
| G1 | GET /ValueSet/{id}/$expand | 2 concepts w/ display | | |
| G2 | POST /ValueSet/$expand?filter= | 1 filtered concept | | |
| H1 | $validate-code (in set) | result: true | | |
| H2 | $validate-code (not in set) | result: false | | |
| H3 | POST $validate-code | result: true | | |
| I1 | POST / (batch) | true then false | | |
