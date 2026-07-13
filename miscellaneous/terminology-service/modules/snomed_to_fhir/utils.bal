// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).

// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerinax/health.fhir.r4;

const int CONCEPT_COLUMN_COUNT = 5;
const int DESCRIPTION_COLUMN_COUNT = 9;
const int RELATIONSHIP_COLUMN_COUNT = 10;
const int DB_STRING_COLUMN_LIMIT = 191;

const string RF2_CONCEPT_PREFIX = "sct2_Concept_Snapshot";
const string RF2_DESCRIPTION_PREFIX = "sct2_Description_Snapshot-en";
const string RF2_TEXT_DEFINITION_PREFIX = "sct2_TextDefinition_Snapshot-en";
const string RF2_RELATIONSHIP_PREFIX = "sct2_Relationship_Snapshot_";

// SNOMED "is a" attribute typeId. Every taxonomic parent link uses this.
public const string SNOMED_IS_A_TYPE_ID = "116680003";

// Functions to parse RF2 Snapshot files and read rows into typed Ballerina records
public isolated function parseSnomedConceptFile(string filePath, int maxRows = -1) returns SnomedConceptRow[]|error {
    string content = check io:fileReadString(filePath);
    string[] lines = regex:split(content, "\\r?\\n");

    SnomedConceptRow[] concepts = [];
    int addedCount = 0;

    foreach string line in lines {
        if line == "" || isHeaderLine(line) {
            continue;
        }

        string[] columns = regex:split(line, "\\t");

        if columns.length() < CONCEPT_COLUMN_COUNT {
            return error("Invalid SNOMED Concept row. Expected at least 5 columns, found "
                + columns.length().toString() + ": " + line);
        }

        SnomedConceptRow concept = {
            id: columns[0],
            effectiveTime: columns[1],
            active: columns[2],
            moduleId: columns[3],
            definitionStatusId: columns[4]
        };

        concepts.push(concept);
        addedCount += 1;

        if maxRows > 0 && addedCount >= maxRows {
            break;
        }
    }

    return concepts;
}

public isolated function parseSnomedDescriptionFile(string filePath, int maxRows = -1) returns SnomedDescriptionRow[]|error {
    string content = check io:fileReadString(filePath);
    string[] lines = regex:split(content, "\\r?\\n");

    SnomedDescriptionRow[] descriptions = [];
    int addedCount = 0;

    foreach string line in lines {
        if line == "" || isHeaderLine(line) {
            continue;
        }

        string[] columns = regex:split(line, "\\t");

        if columns.length() < DESCRIPTION_COLUMN_COUNT {
            return error("Invalid SNOMED Description row. Expected at least 9 columns, found "
                + columns.length().toString() + ": " + line);
        }

        SnomedDescriptionRow description = {
            id: columns[0],
            effectiveTime: columns[1],
            active: columns[2],
            moduleId: columns[3],
            conceptId: columns[4],
            languageCode: columns[5],
            typeId: columns[6],
            term: columns[7],
            caseSignificanceId: columns[8]
        };

        descriptions.push(description);
        addedCount += 1;

        if maxRows > 0 && addedCount >= maxRows {
            break;
        }
    }

    return descriptions;
}

public isolated function parseSnomedTextDefinitionFile(string filePath, int maxRows = -1) returns SnomedTextDefinitionRow[]|error {
    string content = check io:fileReadString(filePath);
    string[] lines = regex:split(content, "\\r?\\n");

    SnomedTextDefinitionRow[] textDefinitions = [];
    int addedCount = 0;

    foreach string line in lines {
        if line == "" || isHeaderLine(line) {
            continue;
        }

        string[] columns = regex:split(line, "\\t");

        if columns.length() < DESCRIPTION_COLUMN_COUNT {
            return error("Invalid SNOMED TextDefinition row. Expected at least 9 columns, found "
                + columns.length().toString() + ": " + line);
        }

        SnomedTextDefinitionRow textDefinition = {
            id: columns[0],
            effectiveTime: columns[1],
            active: columns[2],
            moduleId: columns[3],
            conceptId: columns[4],
            languageCode: columns[5],
            typeId: columns[6],
            term: columns[7],
            caseSignificanceId: columns[8]
        };

        textDefinitions.push(textDefinition);
        addedCount += 1;

        if maxRows > 0 && addedCount >= maxRows {
            break;
        }
    }

    return textDefinitions;
}

public isolated function parseSnomedRelationshipFile(string filePath, int maxRows = -1) returns SnomedRelationshipRow[]|error {
    string content = check io:fileReadString(filePath);
    string[] lines = regex:split(content, "\\r?\\n");

    SnomedRelationshipRow[] relationships = [];
    int addedCount = 0;

    foreach string line in lines {
        if line == "" || isHeaderLine(line) {
            continue;
        }

        string[] columns = regex:split(line, "\\t");

        if columns.length() < RELATIONSHIP_COLUMN_COUNT {
            return error("Invalid SNOMED Relationship row. Expected at least 10 columns, found "
                + columns.length().toString() + ": " + line);
        }

        SnomedRelationshipRow relationship = {
            id: columns[0],
            effectiveTime: columns[1],
            active: columns[2],
            moduleId: columns[3],
            sourceId: columns[4],
            destinationId: columns[5],
            relationshipGroup: columns[6],
            typeId: columns[7],
            characteristicTypeId: columns[8],
            modifierId: columns[9]
        };

        relationships.push(relationship);
        addedCount += 1;

        if maxRows > 0 && addedCount >= maxRows {
            break;
        }
    }

    return relationships;
}

public isolated function getActiveConcepts(SnomedConceptRow[] concepts) returns SnomedConceptRow[] {
    SnomedConceptRow[] activeConcepts = [];

    foreach SnomedConceptRow concept in concepts {
        if concept.active == "1" {
            activeConcepts.push(concept);
        }
    }

    return activeConcepts;
}

public isolated function getActiveDescriptions(SnomedDescriptionRow[] descriptions) returns SnomedDescriptionRow[] {
    SnomedDescriptionRow[] activeDescriptions = [];

    foreach SnomedDescriptionRow description in descriptions {
        if description.active == "1" {
            activeDescriptions.push(description);
        }
    }

    return activeDescriptions;
}

public isolated function getActiveTextDefinitions(SnomedTextDefinitionRow[] textDefinitions) returns SnomedTextDefinitionRow[] {
    SnomedTextDefinitionRow[] activeTextDefinitions = [];

    foreach SnomedTextDefinitionRow textDefinition in textDefinitions {
        if textDefinition.active == "1" {
            activeTextDefinitions.push(textDefinition);
        }
    }

    return activeTextDefinitions;
}

public isolated function isFsn(SnomedDescriptionRow description) returns boolean {
    return description.typeId == SNOMED_FSN_TYPE_ID;
}

public isolated function isSynonym(SnomedDescriptionRow description) returns boolean {
    return description.typeId == SNOMED_SYNONYM_TYPE_ID;
}

// Build a map from child concept SCTID to one chosen parent SCTID.
// Filters to active is-a rows (typeId = 116680003) and keeps the first
// destinationId seen per sourceId — deterministic w.r.t. RF2 file order.
// SNOMED is a polyhierarchy so many children have multiple is-a parents; this
// POC-scope simplification stores only one (Section 7 of the conformance doc).
public isolated function buildParentByChildMap(SnomedRelationshipRow[] relationships) returns map<string> {
    map<string> parentByChild = {};
    foreach SnomedRelationshipRow r in relationships {
        if r.active != "1" || r.typeId != SNOMED_IS_A_TYPE_ID {
            continue;
        }
        if parentByChild.hasKey(r.sourceId) {
            continue;
        }
        parentByChild[r.sourceId] = r.destinationId;
    }
    return parentByChild;
}

// Parse the RF2 Relationship Snapshot and reduce it to the parent-by-child map
// in one pass, streaming the file line-by-line
public isolated function streamSnomedRelationshipsToParentMap(string filePath) returns [map<string>, int]|error {
    map<string> parentByChild = {};
    int rowsRead = 0;

    stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
    record {|string value;|}|io:Error? next = lineStream.next();
    while next is record {|string value;|} {
        string line = next.value;
        if line != "" && !isHeaderLine(line) {
            string[] cols = regex:split(line, "\\t");
            if cols.length() >= RELATIONSHIP_COLUMN_COUNT {
                rowsRead += 1;
                // Only four columns matter: active (2), sourceId (4),
                // destinationId (5), typeId (7). Rows failing either filter are
                // dropped without ever building a record.
                if cols[2] == "1" && cols[7] == SNOMED_IS_A_TYPE_ID {
                    string sourceId = cols[4];
                    if !parentByChild.hasKey(sourceId) {
                        parentByChild[sourceId] = cols[5];
                    }
                }
            }
        }
        next = lineStream.next();
    }
    io:Error? closeResult = lineStream.close();
    if next is io:Error {
        return next;
    }
    if closeResult is io:Error {
        return closeResult;
    }
    return [parentByChild, rowsRead];
}

type ConceptDescriptions record {|
    string? fsn;
    string[] synonyms;
    string? caseSignificanceId;
|};

isolated function streamDescriptionIndex(string filePath) returns [map<ConceptDescriptions>, int]|error {
    map<ConceptDescriptions> index = {};
    int rowsRead = 0;

    stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
    record {|string value;|}|io:Error? next = lineStream.next();
    while next is record {|string value;|} {
        string line = next.value;
        if line != "" && !isHeaderLine(line) {
            string[] cols = regex:split(line, "\\t");
            if cols.length() >= DESCRIPTION_COLUMN_COUNT {
                rowsRead += 1;
                if cols[2] == "1" {
                    string conceptId = cols[4];
                    string typeId = cols[6];
                    string term = cols[7];
                    string caseSig = cols[8];
                    ConceptDescriptions acc = index[conceptId] ?: {fsn: (), synonyms: [], caseSignificanceId: ()};
                    if typeId == SNOMED_FSN_TYPE_ID {
                        if acc.fsn is () {
                            acc.fsn = term;
                        }
                        if acc.caseSignificanceId is () {
                            acc.caseSignificanceId = caseSig;
                        }
                    } else if typeId == SNOMED_SYNONYM_TYPE_ID {
                        acc.synonyms.push(term);
                        if acc.caseSignificanceId is () {
                            acc.caseSignificanceId = caseSig;
                        }
                    }
                    index[conceptId] = acc;
                }
            }
        }
        next = lineStream.next();
    }
    io:Error? closeResult = lineStream.close();
    if next is io:Error {
        return next;
    }
    if closeResult is io:Error {
        return closeResult;
    }
    return [index, rowsRead];
}

isolated function streamTextDefinitionIndex(string filePath) returns [map<string>, int]|error {
    map<string> index = {};
    int rowsRead = 0;

    stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
    record {|string value;|}|io:Error? next = lineStream.next();
    while next is record {|string value;|} {
        string line = next.value;
        if line != "" && !isHeaderLine(line) {
            string[] cols = regex:split(line, "\\t");
            if cols.length() >= DESCRIPTION_COLUMN_COUNT {
                rowsRead += 1;
                if cols[2] == "1" {
                    string conceptId = cols[4];
                    if !index.hasKey(conceptId) {
                        index[conceptId] = cols[7];
                    }
                }
            }
        }
        next = lineStream.next();
    }
    io:Error? closeResult = lineStream.close();
    if next is io:Error {
        return next;
    }
    if closeResult is io:Error {
        return closeResult;
    }
    return [index, rowsRead];
}

// Stream the Concept Snapshot and build one SnomedConceptImport per active
// concept, joining against the pre-built description and text-definition
// indexes.
isolated function streamConceptImports(string filePath, map<ConceptDescriptions> descIndex, map<string> defIndex) returns [SnomedConceptImport[], int]|error {
    SnomedConceptImport[] result = [];
    int rowsRead = 0;

    stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
    record {|string value;|}|io:Error? next = lineStream.next();
    while next is record {|string value;|} {
        string line = next.value;
        if line != "" && !isHeaderLine(line) {
            string[] cols = regex:split(line, "\\t");
            if cols.length() >= CONCEPT_COLUMN_COUNT {
                rowsRead += 1;
                if cols[2] == "1" {
                    string code = cols[0];
                    ConceptDescriptions? cd = descIndex[code];
                    string? fsn = cd?.fsn;
                    string[] synonyms = cd?.synonyms ?: [];

                    // Display fallback: first active synonym -> FSN -> code.
                    string display = synonyms.length() > 0 ? synonyms[0] : (fsn ?: code);

                    // Definition fallback: active TextDefinition -> FSN -> null.
                    string? textDef = defIndex[code];
                    string? definition = textDef is string ? textDef : fsn;

                    result.push({
                        code: code,
                        display: display,
                        definition: definition,
                        effectiveTime: cols[1],
                        active: cols[2],
                        moduleId: cols[3],
                        definitionStatusId: cols[4],
                        fsn: fsn,
                        synonyms: synonyms,
                        caseSignificanceId: cd?.caseSignificanceId
                    });
                }
            }
        }
        next = lineStream.next();
    }
    io:Error? closeResult = lineStream.close();
    if next is io:Error {
        return next;
    }
    if closeResult is io:Error {
        return closeResult;
    }
    return [result, rowsRead];
}

isolated function isHeaderLine(string line) returns boolean {
    return line.startsWith("id\t");
}

public isolated function truncate191(string? value) returns string? {
    if value is () {
        return ();
    }
    if value.length() <= DB_STRING_COLUMN_LIMIT {
        return value;
    }
    return value.substring(0, DB_STRING_COLUMN_LIMIT);
}

public isolated function deriveSnomedDate(string? version) returns string {
    if version is () || version.length() != 8 {
        return "";
    }
    return version.substring(0, 4) + "-" + version.substring(4, 6) + "-" + version.substring(6, 8);
}

public isolated function findRf2File(string dirPath, string prefix) returns string|error {
    string? found = check searchRf2File(dirPath, prefix);
    if found is string {
        return found;
    }
    return error(string `RF2 file with prefix '${prefix}' not found under ${dirPath}`);
}

isolated function searchRf2File(string dirPath, string prefix) returns string?|error {
    boolean exists = check file:test(dirPath, file:EXISTS);
    if !exists {
        return ();
    }
    file:MetaData[] entries = check file:readDir(dirPath);
    foreach file:MetaData entry in entries {
        string name = getBaseName(entry.absPath);
        if !entry.dir && name.startsWith(prefix) && name.endsWith(".txt") {
            return entry.absPath;
        }
    }
    foreach file:MetaData entry in entries {
        if entry.dir {
            string? nested = check searchRf2File(entry.absPath, prefix);
            if nested is string {
                return nested;
            }
        }
    }
    return ();
}

isolated function getBaseName(string path) returns string {
    string[] parts = regex:split(path, "[\\\\/]");
    return parts[parts.length() - 1];
}

// Group parsed RF2 rows into per-concept import records.
public isolated function assembleSnomedConceptImports(
        SnomedConceptRow[] concepts,
        SnomedDescriptionRow[] descriptions,
        SnomedTextDefinitionRow[] textDefinitions
) returns SnomedConceptImport[] {
    map<SnomedDescriptionRow[]> descByConcept = {};
    foreach SnomedDescriptionRow d in descriptions {
        if d.active != "1" {
            continue;
        }
        SnomedDescriptionRow[] bucket = descByConcept[d.conceptId] ?: [];
        bucket.push(d);
        descByConcept[d.conceptId] = bucket;
    }

    map<string> defByConcept = {};
    foreach SnomedTextDefinitionRow t in textDefinitions {
        if t.active != "1" {
            continue;
        }
        // If a concept has multiple text definitions we keep the first one seen.
        if !defByConcept.hasKey(t.conceptId) {
            defByConcept[t.conceptId] = t.term;
        }
    }

    SnomedConceptImport[] result = [];
    foreach SnomedConceptRow c in concepts {
        if c.active != "1" {
            continue;
        }
        SnomedDescriptionRow[] descs = descByConcept[c.id] ?: [];

        string? fsn = ();
        string[] synonyms = [];
        string? caseSig = ();
        foreach SnomedDescriptionRow d in descs {
            if isFsn(d) && fsn is () {
                fsn = d.term;
                if caseSig is () {
                    caseSig = d.caseSignificanceId;
                }
            } else if isSynonym(d) {
                synonyms.push(d.term);
                if caseSig is () {
                    caseSig = d.caseSignificanceId;
                }
            }
        }

        string display = synonyms.length() > 0 ? synonyms[0] : (fsn ?: c.id);
        
        string? textDef = defByConcept[c.id];
        string? definition = textDef is string ? textDef : fsn;

        SnomedConceptImport item = {
            code: c.id,
            display: display,
            definition: definition,
            effectiveTime: c.effectiveTime,
            active: c.active,
            moduleId: c.moduleId,
            definitionStatusId: c.definitionStatusId,
            fsn: fsn,
            synonyms: synonyms,
            caseSignificanceId: caseSig
        };
        result.push(item);
    }

    return result;
}

// Build the SNOMED CodeSystem metadata resource
public isolated function buildSnomedCodeSystemMetadata(string? version) returns r4:CodeSystem {
    string effectiveVersion = version ?: "";
    r4:CodeSystem codeSystem = {
        resourceType: "CodeSystem",
        id: SNOMED_CODE_SYSTEM_ID,
        url: SNOMED_SYSTEM_URL,
        name: SNOMED_CODE_SYSTEM_NAME,
        title: SNOMED_CODE_SYSTEM_TITLE,
        status: r4:CODE_STATUS_ACTIVE,
        content: r4:CODE_CONTENT_FRAGMENT,
        caseSensitive: true,
        hierarchyMeaning: r4:CODE_HIERARCHYMEANING_IS_A,
        publisher: SNOMED_PUBLISHER,
        date: deriveSnomedDate(version)
    };
    if effectiveVersion != "" {
        codeSystem.version = effectiveVersion;
    }
    return codeSystem;
}

// Convert a single SnomedConceptImport into a full-fidelity r4:CodeSystemConcept.
public isolated function snomedConceptImportToR4(SnomedConceptImport item) returns r4:CodeSystemConcept {
    r4:CodeSystemConceptDesignation[] designations = [];

    string? fsn = item.fsn;
    if fsn is string {
        designations.push({
            language: "en",
            value: fsn,
            use: {
                system: SNOMED_SYSTEM_URL,
                code: SNOMED_FSN_TYPE_ID,
                display: "Fully specified name"
            }
        });
    }

    foreach string synonym in item.synonyms {
        designations.push({
            language: "en",
            value: synonym,
            use: {
                system: SNOMED_SYSTEM_URL,
                code: SNOMED_SYNONYM_TYPE_ID,
                display: "Synonym"
            }
        });
    }

    r4:CodeSystemConceptProperty[] properties = [
        {code: "active", valueBoolean: item.active == "1"},
        {code: "moduleId", valueString: item.moduleId},
        {code: "definitionStatusId", valueString: item.definitionStatusId},
        {code: "effectiveTime", valueString: item.effectiveTime}
    ];

    r4:CodeSystemConcept concept = {
        code: item.code,
        display: item.display,
        property: properties
    };

    if item.definition is string {
        concept.definition = item.definition;
    }

    if designations.length() > 0 {
        concept.designation = designations;
    }

    return concept;
}