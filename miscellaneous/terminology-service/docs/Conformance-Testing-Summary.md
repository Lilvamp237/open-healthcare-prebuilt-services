# FHIR conformance testing — approach and initial findings

## What I did

To check whether our terminology operations return spec-compliant FHIR (review
note: "check whether the operation behaviour is conformant to the standard
ones"), I validated our service's actual responses with the **official HL7 FHIR
validator** (`validator_cli.jar`, v6.9.12).

Method:
1. Call each operation on the running service and save the response to a file.
2. Run the HL7 validator against each file, targeting FHIR R4, structural
   validation only (`-version 4.0.1 -tx n/a`).
3. Run the same operations against **both SNOMED and LOINC** so differences
   between them become findings.

## Why this tool

- It is **HL7's own reference validator** — the de-facto standard for checking
  FHIR conformance, the same engine behind the online validator and the IG
  publisher. Open source, free to use.
- Its verdict is objective: a response either satisfies the base FHIR
  StructureDefinitions and constraints, or it doesn't.
- Running both code systems through it turns "SNOMED vs LOINC" differences into
  evidence about where a defect lives.

## Initial findings

### Finding 1 (structural, confirmed) — `$lookup` property rendering

The validator **fails** our SNOMED `$lookup` response with 2 errors:

- `Parameters.parameter.part` is an empty array (`part: []`), which FHIR forbids.
- Constraint `inv-1`: a parameter must have exactly one of value / resource /
  part — ours has none.

Root cause: the shared function that turns a concept property into a FHIR
parameter handles only string and Coding values — it has no branch for boolean
properties, and it assigns `part` unconditionally. SNOMED's `active` property is
a boolean, so it produces `{"name":"property","part":[]}`.

**Scope**: this is in shared response-building code, not SNOMED-specific. The
LOINC `$lookup` response *passes* the validator only because LOINC has no
boolean properties — but the same code path still emits value-less `property`
parameters for LOINC (flagged as information notes). So it's one shared defect
with two symptoms.

### Finding 2 (behavioural) — `$find-code` with a `system` filter

`$find-code` works without a `system` parameter but errors when one is supplied.
The query filters on a `url` column that exists on the `codesystems` table, not
on `concepts`, so the SQL fails. Affects both code systems. The validator can't
catch this — it's a wrong-behaviour issue, not a malformed-response issue.

### Finding 3 (behavioural) — POST `$expand` with query parameters

POST `$expand` with the ValueSet `url` and `filter` in the query string doesn't
resolve the ValueSet. The handler reads those from the request body on a POST,
not the query string. The GET-by-id form works. Affects both code systems.

## Structural vs behavioural — why the split matters

- **Structural** findings (Finding 1) are caught automatically by the validator
  and are objective. Usually small, localised fixes.
- **Behavioural** findings (Findings 2, 3) are valid FHIR that does the wrong
  thing — the validator passes them; only comparing actual-vs-expected catches
  them.

## Status of this as a "test suite"

This is a **conformance audit**, not an automated regression suite:

- It establishes the *expected* result for each operation and records where we
  diverge — which is exactly what a first conformance pass should do.
- It is repeatable (fixed commands, fixed flags, saved outputs) and produces a
  citable evidence trail.
- It is the foundation for an automated suite later: once expected outputs are
  known, the same cases can be encoded as Postman/Newman or Ballerina tests that
  run on every build.

## Next steps

1. Complete the full grid — every operation × SNOMED and LOINC (in progress).
2. Fix Finding 1 (add the boolean branch), then re-run the validator to show a
   clean before/after.
3. Fix Findings 2 and 3.
4. Convert the confirmed cases into an automated regression suite.
