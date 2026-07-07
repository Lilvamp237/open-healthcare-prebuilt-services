# SNOMED CT → FHIR — POC Implementation Guide

This document explains **what** the SNOMED CT proof-of-concept does, **how** it
works, and **why** each part is built the way it is. It follows the data from
the moment a file is uploaded to the moment a FHIR client can query it.

For the reasoning behind each choice, see the companion
**SNOMED-POC-Design-Decisions.md**.

---

## 1. What the POC does (in one paragraph)

A client uploads a SNOMED CT RF2 release (a zip of tab-separated text files).
The server unpacks it, reads the relevant files, converts each SNOMED concept
into a FHIR-shaped record, and stores it in the **same `codesystems` and
`concepts` database tables that already hold LOINC**. Once loaded, standard FHIR
terminology operations — `$lookup`, `$find-code`, `$validate-code`, and
`$subsumes` — work against SNOMED exactly as they do against LOINC.

---

## 2. The end-to-end flow

```
Client uploads zip
      │
      ▼
[1] /$upload  ──── unzip, then start a background worker, return 201 immediately
      │
      ▼
[2] Locate + stream the RF2 files (Concept, Description, TextDefinition, Relationship)
      │
      ▼
[3] Join descriptions onto concepts → one import record per active concept
      │
      ▼
[4] Shape into FHIR (CodeSystem metadata + per-concept resources)
      │
      ▼
[5] Write to DB:  Pass 1 insert concepts │ Pass 2 link parents
      │
      ▼
Queryable via $lookup / $find-code / $validate-code / $subsumes
```

---

## 3. Step by step

### Step 1 — Upload endpoint (runs in the background)

**What:** The SNOMED branch of `/$upload` starts a background worker and returns
`201 Created` right away.

**Why:** A full import takes 30–60 minutes — far longer than HTTP and client
timeouts allow. If the client had to wait, the request would always time out.

**How** (`terminology_connect.bal`):
```ballerina
else if typeHeader == SNOMED {
    string? version = payload.getQueryParamValue("snomed-version");
    _ = start runSnomedImportAsync(dirPath + ZIP_FILE_EXTRACTION_PATH, version, dirPath);
    log:printInfo("SNOMED import scheduled in background; check server logs for completion.");
    return ();   // 201 sent now; the worker keeps running
}
```

The worker logs a summary when it finishes and deletes the temp directory.
Progress is visible in the server logs, not the HTTP response.

---

### Step 2 — Locate and stream the RF2 files

**What:** Find the four RF2 files by name prefix, then read each one
**line-by-line** rather than loading the whole file into memory.

**Why:**
- RF2 filenames contain the release date (e.g.
  `sct2_Concept_Snapshot_INT_20260401.txt`), which changes every release, so we
  match by prefix, not exact name.
- The Description (1.7M rows) and Relationship (3.5M rows) files are huge.
  Reading a whole file at once allocated several GB of memory and crashed the
  server with `OutOfMemoryError`. Streaming one line at a time keeps memory flat.

**How** (`utils.bal`) — every parser uses this shape:
```ballerina
stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
record {|string value;|}|io:Error? next = lineStream.next();
while next is record {|string value;|} {
    string line = next.value;
    if line != "" && !isHeaderLine(line) {
        string[] cols = regex:split(line, "\\t");
        // ...reduce this row into the result, then discard it...
    }
    next = lineStream.next();
}
```

The file finder walks the extracted zip recursively:
```ballerina
string conceptFilePath = check findRf2File(dirPath, RF2_CONCEPT_PREFIX);        // sct2_Concept_Snapshot
string descriptionFilePath = check findRf2File(dirPath, RF2_DESCRIPTION_PREFIX); // sct2_Description_Snapshot-en
```

---

### Step 3 — Join descriptions onto concepts

**What:** Build an in-memory index of each concept's active descriptions
(FSN + synonyms), then stream the Concept file and attach the right text to each
concept.

**Why:** A concept's human-readable label lives in a *separate* file
(Description) linked by `conceptId`. We must join the two. Doing it with a
compact index — keeping only the FSN and synonyms, not the full 9-column rows —
keeps memory low.

**How** (`utils.bal`) — display and definition use fallback chains:
```ballerina
string display = synonyms.length() > 0 ? synonyms[0] : (fsn ?: code);
//               first active synonym  →  FSN  →  the code itself

string? textDef = defIndex[code];
string? definition = textDef is string ? textDef : fsn;
//                   text definition   →  FSN  →  null
```

- **Display:** first active synonym, else the FSN, else the code (last resort).
- **Definition:** the text definition if the concept has one (only ~5% do),
  otherwise fall back to the FSN.

---

### Step 4 — Shape into FHIR

**What:** Build one FHIR `CodeSystem` metadata resource and one
`CodeSystemConcept` per concept.

**Why:** The database stores FHIR resources (as bytes). Shaping the data into
FHIR here means `$lookup` can return it directly with no further conversion.

**How** — the CodeSystem is **metadata only** (`utils.bal`):
```ballerina
r4:CodeSystem codeSystem = {
    id: "snomed-ct",
    url: "http://snomed.info/sct",
    name: "SNOMEDCT",
    title: "SNOMED Clinical Terms",
    status: r4:CODE_STATUS_ACTIVE,
    content: r4:CODE_CONTENT_FRAGMENT,   // "fragment" = concepts stored separately
    caseSensitive: true,
    hierarchyMeaning: r4:CODE_HIERARCHYMEANING_IS_A,
    publisher: "SNOMED International"
    // NOTE: no concept[] inline — the 380K concepts live in the concepts table
};
```

Each concept carries its FSN + synonyms as **designations** and its SNOMED
metadata as **properties**:
```ballerina
r4:CodeSystemConceptProperty[] properties = [
    {code: "active", valueBoolean: item.active == "1"},
    {code: "moduleId", valueString: item.moduleId},
    {code: "definitionStatusId", valueString: item.definitionStatusId},
    {code: "effectiveTime", valueString: item.effectiveTime}
];
```

---

### Step 5 — Write to the database (two passes)

SNOMED is a hierarchy: each concept can have a **parent**. But the database
stores the parent as an internal row-id, which isn't known until the parent row
is inserted. So we insert in two passes.

**Pass 1 — insert concepts** (`snomed_import.bal`), 1000 at a time, parents left
empty. As each batch is saved, we remember the code → row-id mapping:
```ballerina
store_h2:ConceptInsert conceptInsert = {
    code: item.code,
    display: snomed:truncate191(item.display),       // fit VARCHAR(191)
    definition: snomed:truncate191(item.definition),
    concept: conceptBytes,                            // full FHIR resource (bytes)
    parentConceptId: (),                              // null for now
    codesystemCodeSystemId: codeSystemId
};
```

**Pass 2 — link parents** (`snomed_import.bal`): walk the child→parent map (built
from active *is-a* relationships), translate both sides to row-ids, and update
each child:
```ballerina
int? childDbId = dbIdByCode[childSctid];
int? parentDbId = dbIdByCode[parentSctid];
if childDbId is () || parentDbId is () { skipped += 1; continue; }  // parent not imported
_ = sClient->/concepts/[childDbId].put({parentConceptId: parentDbId});
```

**Why two passes:** SNOMED concepts can have several parents in any order, so
there's no simple "insert parents first" ordering. Inserting everything first,
then linking, sidesteps the problem entirely.

---

## 4. What gets imported vs filtered out

The POC imports **active concepts only**.

| RF2 file | What we keep | What we drop |
|---|---|---|
| Concept | Active concepts → one row each | **Inactive concepts** |
| Description | Folded into each concept (FSN + synonyms) | Inactive descriptions |
| TextDefinition | Folded into each concept (definition) | Inactive; extras beyond the first |
| Relationship | Reduced to one parent per concept | Inactive, non-*is-a*, and 2nd+ parents |

A concept with **no parent is still imported** — the SNOMED root concept is a
normal row with an empty parent. Only *inactive* concepts are excluded.

> **Difference from LOINC:** The existing LOINC importer keeps **every** row
> (active, trial, deprecated) and just records the status as a property. SNOMED
> currently keeps active only. **In the real system we will import inactive
> concepts too** (marked with the `active = false` property) so that
> `$validate-code` can recognise a retired code instead of reporting it as
> unknown. This is a small change — remove the active-only filter — deferred
> until after the POC.

---

## 5. The result (from a full International release)

```
conceptsRead=530648, conceptsImported=379986, descriptionsRead=1700081,
textDefinitionsRead=18994, relationshipsRead=3556987, parentsLinked=379985
```

- 379,986 active concepts imported (150,662 inactive filtered out).
- 379,985 parents linked — exactly one fewer than imported, because the single
  **root concept** correctly has no parent. That 1:1-minus-root result is the
  sign of a clean import.

---

## 6. How to verify

```
# Label lookup
GET /fhir/r4/CodeSystem/$lookup?system=http://snomed.info/sct&code=73211009
    → display: "Diabetes mellitus"

# Metadata
GET /fhir/r4/CodeSystem/snomed-ct
    → title: "SNOMED Clinical Terms", content: "fragment"

# Hierarchy (proves parent linking worked)
GET /fhir/r4/CodeSystem/$subsumes?system=http://snomed.info/sct&codeA=73211009&codeB=44054006
    → outcome: "subsumes"   (Diabetes mellitus is an ancestor of type-2 diabetes)
```

---

## 7. Known limitations and next steps

| Area | POC now | Real system |
|---|---|---|
| Inactive concepts | Excluded | Import all, mark `active=false` |
| Parent linking speed | ~380K single UPDATEs (~30–40 min) | One bulk SQL UPDATE (~minutes) |
| Multiple parents | One parent per concept | Full is-a graph in a relationships table |
| Fast `$subsumes` | Walks the single-parent chain | Precomputed closure table |
| Preferred term | First active synonym | Use the Language Refset for the true PT |
| `$translate` | Not implemented | ConceptMap tables |
| Source folder | `Snapshot/` (current state) | `Snapshot/` (never `Full/`) |
