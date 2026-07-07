# SNOMED CT → FHIR — POC Design Decisions

This document records the key decisions we made building the SNOMED CT
proof-of-concept, and **why** we made each one. Several decisions were forced by
problems we hit along the way — those are noted.

For how the code actually works, see the companion
**SNOMED-POC-Implementation.md**.

---

## The problems that shaped the design

Three problems drove the biggest choices:

1. **Scale** — SNOMED has ~380K active concepts vs LOINC's ~100K. The LOINC
   loading method doesn't scale.
2. **Timeouts** — a full import takes 30–60 min; the upload request timed out.
3. **Out of memory** — reading whole files into memory crashed the server.

🖼 **Fig. 1:** Reading whole files peaked at 4–6 GB and crashed; streaming
line-by-line keeps peak memory under 1 GB.

---

## Architecture & storage

**1. SNOMED uses its own import path, not the shared LOINC one.**
The shared path packs every concept into one giant resource and starts one
background task per concept. Even though it works for LOINC, it exhausts memory
and the database pool at SNOMED's scale.

**2. Store the CodeSystem as metadata only (`content = fragment`).**
Embedding 380K concepts would create a ~500 MB blob re-read on every request.
The concepts live in their own table instead.

**3. Keep parsing and database code in separate layers.**
The parser has no database code, so it can be unit-tested and understood on its
own.

**4. Truncate text for the search columns, keep full text in the resource.**
The `display`/`definition` columns are capped at 191 characters for indexing;
the full text stays in the stored FHIR resource that `$lookup` returns.

---

## Data mapping (RF2 → FHIR)

This is where SNOMED's file format meets FHIR. Most SNOMED values are **not** a
single RF2 column: some are fixed identifiers, the display text comes from one
file, and the hierarchy from another. These decisions record how each piece is
mapped.

### Field mapping at a glance

| FHIR / DB target | RF2 source | Rule |
|---|---|---|
| `codesystems.id` | fixed | `snomed-ct` |
| `codesystems.url` | fixed | `http://snomed.info/sct` |
| `codesystems.name` / `title` / `publisher` | fixed | `SNOMEDCT` / `SNOMED Clinical Terms` / `SNOMED International` |
| `codesystems.version` | release date | e.g. `20260401` |
| `codesystems.date` | release date | converted `20260401` → `2026-04-01` |
| `codesystems.status` | fixed | `active` |
| `concepts.code` | `Concept.id` (SCTID) | copied directly |
| `concepts.display` | `Description.term` | first active synonym → FSN → code |
| `concepts.definition` | `TextDefinition.term` | text definition → FSN → empty |
| concept designations | `Description` rows | FSN (typeId 900000000000003001) + synonyms (900000000000013009) |
| concept properties | `Concept` columns | `active`, `moduleId`, `definitionStatusId`, `effectiveTime` |
| `concepts.parentConceptId` | `Relationship` | first active *is-a* (typeId 116680003) parent |
| `concepts.codesystemCodeSystemId` | — | foreign key to the SNOMED row |

### The mapping decisions

**5. Read four RF2 files, ignore the rest.**
We parse **Concept**, **Description**, **TextDefinition**, and **Relationship**.
We ignore StatedRelationship, RelationshipConcreteValues, Identifier, OWL, and
the refset files. Those four carry everything `$lookup` and `$subsumes` need; the
rest support advanced features that are out of POC scope.

**6. Use the inferred Relationship file, not StatedRelationship.**
The inferred `Relationship` file is the computed, normalised hierarchy that
terminology servers rely on. `StatedRelationship` is the author's pre-computation
view — not what we want for querying.

**7. Only active *is-a* relationships build the hierarchy.**
A relationship is a parent link only when its type is *is-a* (typeId
`116680003`) and it is active. All other relationship types (finding site,
causative agent, and so on) are dropped — they belong to advanced SNOMED
reasoning, not the POC's parent/child tree.

**8. Fallback chains for display and definition.**
Display = first synonym → FSN → code. Definition = text definition → FSN →
empty. The true "preferred term" needs the Language Refset, which we don't parse
in the POC, so the first active synonym is a good stand-in.

**9. SNOMED metadata becomes FHIR properties and designations.**
`active`, `moduleId`, `definitionStatusId`, and `effectiveTime` become concept
**properties**; the FSN and synonyms become **designations**, each tagged with
its SNOMED type and `language: "en"`. FHIR supports both natively, so no schema
change is needed.

**10. Deterministic "first wins", English only.**
Where a concept has several candidates (multiple synonyms, definitions, or
parents) we keep the **first one in RF2 file order** — stable within a release,
so the same input always produces the same output. We read only the English
(`-en`) description files.

**11. Fixed CodeSystem identity; version and date from the release.**
The CodeSystem's `id`, `url`, `name`, `title`, and `publisher` are fixed
constants, not RF2 data — SNOMED's identity is standardised. Only the `version`
(the release date) and `date` (the same date in ISO form) change per release.

**12. One parent per concept (POC simplification).**
SNOMED allows several parents, but the schema has one parent column. We store the
first active *is-a* parent for the POC; the full graph is a real-system item.

---

## Performance & reliability

**13. Run the import in the background.**
The upload returns immediately and reports progress in the logs, avoiding the
HTTP timeout. (Trade-off: the client checks logs, not the response.)

**14. Two-pass insert to set parents.**
The parent link needs a row-id that doesn't exist until the parent is inserted.
So we insert everything first, then link. Cost: ~380K updates (~30–40 min). This
is the main runtime cost and needs to speed up later.

**15. Stream every file line-by-line (the memory fix).**
The first version read whole files and crashed with out-of-memory errors even
after raising the Java heap. Streaming keeps peak memory under 1 GB regardless of
release size.

---

## Consistency with LOINC

**16. SNOMED imports active only, while LOINC imports everything.**
This is a known difference. The plan for the real system is to align them by
importing inactive SNOMED concepts too, marked `active = false`, so
`$validate-code` can recognise retired codes. This change is deferred until after
the POC.

---

## What is deliberately left for the real system

| Item | POC | Real system |
|---|---|---|
| Inactive concepts | Excluded | Imported, marked active=false |
| Multiple parents | One per concept | Full is-a graph |
| Fast $subsumes | Walk parent chain | Closure table |
| $translate | Not implemented | ConceptMap tables |
| Preferred term | First synonym | Language Refset |
| Parent-link speed | 380K single updates | One bulk update |
| Non-is-a relationships | Dropped | Stored for ECL / advanced queries |
| Languages | English only | Language Refset + dialects |

---

## In one sentence

> Store SNOMED the way FHIR expects, map only the RF2 files the POC needs
> (concept, description, definition, is-a hierarchy), and make the pipeline
> survive real-world scale — leaving the richer graph, translation, and
> multi-language features for the production system.
