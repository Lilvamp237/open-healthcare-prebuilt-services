import ballerina/io;
import ballerina/regex;

const int CONCEPT_COLUMN_COUNT = 5;
const int DESCRIPTION_COLUMN_COUNT = 9;

// Parses RF2 Concept Snapshot TSV file.
// This only reads RF2 rows into typed Ballerina records.
// It does not create FHIR JSON and does not write to DB.
public function parseSnomedConceptFile(string filePath, int maxRows = -1) returns SnomedConceptRow[]|error {
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

// Parses RF2 Description Snapshot TSV file.
// This includes FSNs and synonyms.
public function parseSnomedDescriptionFile(string filePath, int maxRows = -1) returns SnomedDescriptionRow[]|error {
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

// Parses RF2 TextDefinition Snapshot TSV file.
// This has the same column structure as Description Snapshot.
public function parseSnomedTextDefinitionFile(string filePath, int maxRows = -1) returns SnomedTextDefinitionRow[]|error {
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

public function getActiveConcepts(SnomedConceptRow[] concepts) returns SnomedConceptRow[] {
    SnomedConceptRow[] activeConcepts = [];

    foreach SnomedConceptRow concept in concepts {
        if concept.active == "1" {
            activeConcepts.push(concept);
        }
    }

    return activeConcepts;
}

public function getActiveDescriptions(SnomedDescriptionRow[] descriptions) returns SnomedDescriptionRow[] {
    SnomedDescriptionRow[] activeDescriptions = [];

    foreach SnomedDescriptionRow description in descriptions {
        if description.active == "1" {
            activeDescriptions.push(description);
        }
    }

    return activeDescriptions;
}

public function getActiveTextDefinitions(SnomedTextDefinitionRow[] textDefinitions) returns SnomedTextDefinitionRow[] {
    SnomedTextDefinitionRow[] activeTextDefinitions = [];

    foreach SnomedTextDefinitionRow textDefinition in textDefinitions {
        if textDefinition.active == "1" {
            activeTextDefinitions.push(textDefinition);
        }
    }

    return activeTextDefinitions;
}

public function isFsn(SnomedDescriptionRow description) returns boolean {
    return description.typeId == SNOMED_FSN_TYPE_ID;
}

public function isSynonym(SnomedDescriptionRow description) returns boolean {
    return description.typeId == SNOMED_SYNONYM_TYPE_ID;
}

function isHeaderLine(string line) returns boolean {
    return line.startsWith("id\t");
}