// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).

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

// Builds a child -> parents map from the Relationship file, keeping only active
// is-a rows. A concept can have several parents, so values are arrays.
public isolated function streamSnomedIsaAdjacency(string filePath) returns [map<string[]>, int]|error {
    map<string[]> parentsByChild = {};
    int rowsRead = 0;

    stream<string, io:Error?> lineStream = check io:fileReadLinesAsStream(filePath);
    record {|string value;|}|io:Error? next = lineStream.next();
    while next is record {|string value;|} {
        string line = next.value;
        if line != "" && !isHeaderLine(line) {
            string[] cols = regex:split(line, "\\t");
            if cols.length() >= RELATIONSHIP_COLUMN_COUNT {
                rowsRead += 1;
                if cols[2] == "1" && cols[7] == SNOMED_IS_A_TYPE_ID {
                    string sourceId = cols[4];
                    string[] parents = parentsByChild[sourceId] ?: [];
                    parents.push(cols[5]);
                    parentsByChild[sourceId] = parents;
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
    return [parentsByChild, rowsRead];
}

// Returns every ancestor of a concept with its shortest distance. Walks the
// tree level by level, so an ancestor reachable by two paths gets the shorter
// depth. Excludes the concept itself.
public isolated function computeAncestorDepths(string code, map<string[]> parentsByChild) returns map<int> {
    map<int> ancestorDepths = {};

    string[] frontier = parentsByChild[code] ?: [];
    int depth = 1;

    while frontier.length() > 0 {
        string[] nextFrontier = [];
        foreach string ancestor in frontier {
            if ancestorDepths.hasKey(ancestor) {
                continue;
            }
            ancestorDepths[ancestor] = depth;
            string[] grandParents = parentsByChild[ancestor] ?: [];
            foreach string grandParent in grandParents {
                if !ancestorDepths.hasKey(grandParent) {
                    nextFrontier.push(grandParent);
                }
            }
        }
        frontier = nextFrontier;
        depth += 1;
    }

    return ancestorDepths;
}

type ConceptDescriptions record {|
    string? fsn;
    string[] synonyms;
    string? caseSignificanceId;
|};

// Groups active descriptions by concept, splitting them into the fully
// specified name and the synonyms.
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

// Reads the Concept file and joins each row against the description and text
// definition indexes. Display falls back from synonym to FSN to the code, and
// definition falls back from the text definition to the FSN.
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
                // Import all concepts, active and inactive.
                string code = cols[0];
                ConceptDescriptions? descriptions = descIndex[code];
                string? fsn = descriptions?.fsn;
                string[] synonyms = descriptions?.synonyms ?: [];

                string display = synonyms.length() > 0 ? synonyms[0] : (fsn ?: code);

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
                    caseSignificanceId: descriptions?.caseSignificanceId
                });
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

// Trims a value to fit the varchar limit on the concepts table columns.
public isolated function truncate191(string? value) returns string? {
    if value is () {
        return ();
    }
    if value.length() <= DB_STRING_COLUMN_LIMIT {
        return value;
    }
    return value.substring(0, DB_STRING_COLUMN_LIMIT);
}

// Converts an RF2 version stamp (YYYYMMDD) into a FHIR date (YYYY-MM-DD).
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

// Looks for the file in the given directory first, then recurses into any
// subdirectories, since RF2 releases nest their files differently.
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
