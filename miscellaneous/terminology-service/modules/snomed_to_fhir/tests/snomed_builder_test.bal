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

import ballerina/test;
import ballerinax/health.fhir.r4;

@test:Config {}
function testAssembleSnomedConceptImportsPicksSynonymAsDisplay() returns error? {
    SnomedConceptRow[] concepts = check parseSnomedConceptFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Concept_Snapshot_INT_20260401.txt"
    );
    SnomedDescriptionRow[] descriptions = check parseSnomedDescriptionFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Description_Snapshot-en_INT_20260401.txt"
    );

    SnomedConceptImport[] imports = assembleSnomedConceptImports(concepts, descriptions, []);

    test:assertEquals(imports.length(), 1);
    SnomedConceptImport item = imports[0];
    test:assertEquals(item.code, "123456");
    // Synonym wins over FSN for display per spec fallback order.
    test:assertEquals(item.display, "Test concept");
    test:assertEquals(item.fsn, "Test concept (finding)");
    test:assertEquals(item.synonyms.length(), 1);
    test:assertEquals(item.synonyms[0], "Test concept");
    // No TextDefinition passed, so definition falls back to the FSN
    // (Section 7 conformance doc rule).
    test:assertEquals(item.definition, "Test concept (finding)");
}

@test:Config {}
function testSnomedConceptImportToR4EmitsDesignationsAndProperties() {
    SnomedConceptImport item = {
        code: "123456",
        display: "Test concept",
        definition: (),
        effectiveTime: "20260401",
        active: "1",
        moduleId: "900000000000207008",
        definitionStatusId: "900000000000074008",
        fsn: "Test concept (finding)",
        synonyms: ["Test concept"],
        caseSignificanceId: "900000000000448009"
    };

    r4:CodeSystemConcept concept = snomedConceptImportToR4(item);

    test:assertEquals(concept.code, "123456");
    test:assertEquals(concept.display, "Test concept");

    r4:CodeSystemConceptDesignation[]? designations = concept.designation;
    test:assertTrue(designations is r4:CodeSystemConceptDesignation[]);
    test:assertEquals((<r4:CodeSystemConceptDesignation[]>designations).length(), 2);
    test:assertEquals((<r4:CodeSystemConceptDesignation[]>designations)[0].value, "Test concept (finding)");
    test:assertEquals((<r4:CodeSystemConceptDesignation[]>designations)[1].value, "Test concept");

    r4:CodeSystemConceptProperty[]? properties = concept.property;
    test:assertTrue(properties is r4:CodeSystemConceptProperty[]);
    // active + moduleId + definitionStatusId + effectiveTime
    test:assertEquals((<r4:CodeSystemConceptProperty[]>properties).length(), 4);
}

@test:Config {}
function testBuildSnomedCodeSystemMetadataHasFragmentContentAndNoConcepts() {
    r4:CodeSystem cs = buildSnomedCodeSystemMetadata("20260401");

    test:assertEquals(cs.id, SNOMED_CODE_SYSTEM_ID);
    test:assertEquals(cs.url, SNOMED_SYSTEM_URL);
    test:assertEquals(cs.version, "20260401");
    test:assertEquals(cs.date, "2026-04-01");
    test:assertEquals(cs.content, r4:CODE_CONTENT_FRAGMENT);
    test:assertEquals(cs.caseSensitive, true);
    test:assertEquals(cs.hierarchyMeaning, r4:CODE_HIERARCHYMEANING_IS_A);
    // Concepts must NOT be inlined into the metadata resource.
    test:assertEquals(cs.concept, ());
}

@test:Config {}
function testTruncate191() {
    test:assertEquals(truncate191(()), ());
    test:assertEquals(truncate191("short"), "short");

    string longStr = "";
    int i = 0;
    while i < 200 {
        longStr += "x";
        i += 1;
    }
    string? truncated = truncate191(longStr);
    test:assertTrue(truncated is string);
    test:assertEquals((<string>truncated).length(), 191);
}

@test:Config {}
function testParseSnomedRelationshipFile() returns error? {
    SnomedRelationshipRow[] rels = check parseSnomedRelationshipFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Relationship_Snapshot_INT_20260401.txt"
    );

    test:assertEquals(rels.length(), 3);
    // Column mapping sanity check on the first row.
    test:assertEquals(rels[0].id, "1000001");
    test:assertEquals(rels[0].sourceId, "123456");
    test:assertEquals(rels[0].destinationId, "138875005");
    test:assertEquals(rels[0].typeId, SNOMED_IS_A_TYPE_ID);
    test:assertEquals(rels[0].modifierId, "900000000000451002");
}

@test:Config {}
function testBuildParentByChildMapFiltersActiveAndIsA() returns error? {
    SnomedRelationshipRow[] rels = check parseSnomedRelationshipFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Relationship_Snapshot_INT_20260401.txt"
    );

    map<string> parents = buildParentByChildMap(rels);

    // Fixture has: one active is-a (kept), one inactive is-a (dropped), one
    // active non-is-a (dropped).
    test:assertEquals(parents.length(), 1);
    test:assertEquals(parents["123456"], "138875005");
}

@test:Config {}
function testStreamDescriptionIndex() returns error? {
    [map<ConceptDescriptions>, int] result = check streamDescriptionIndex(
        "modules/snomed_to_fhir/tests/resources/sct2_Description_Snapshot-en_INT_20260401.txt"
    );
    map<ConceptDescriptions> index = result[0];

    test:assertEquals(result[1], 2);
    ConceptDescriptions? cd = index["123456"];
    test:assertTrue(cd is ConceptDescriptions);
    ConceptDescriptions c = <ConceptDescriptions>cd;
    test:assertEquals(c.fsn, "Test concept (finding)");
    test:assertEquals(c.synonyms.length(), 1);
    test:assertEquals(c.synonyms[0], "Test concept");
}

@test:Config {}
function testStreamConceptImportsJoinsDescriptions() returns error? {
    [map<ConceptDescriptions>, int] descResult = check streamDescriptionIndex(
        "modules/snomed_to_fhir/tests/resources/sct2_Description_Snapshot-en_INT_20260401.txt"
    );
    // No text definitions passed -> definition should fall back to FSN.
    [SnomedConceptImport[], int] conceptResult = check streamConceptImports(
        "modules/snomed_to_fhir/tests/resources/sct2_Concept_Snapshot_INT_20260401.txt",
        descResult[0],
        {}
    );
    SnomedConceptImport[] imports = conceptResult[0];

    test:assertEquals(conceptResult[1], 1);
    test:assertEquals(imports.length(), 1);
    test:assertEquals(imports[0].code, "123456");
    // Synonym wins for display.
    test:assertEquals(imports[0].display, "Test concept");
    // FSN fallback for definition.
    test:assertEquals(imports[0].definition, "Test concept (finding)");
    test:assertEquals(imports[0].synonyms.length(), 1);
}

@test:Config {}
function testStreamSnomedRelationshipsToParentMap() returns error? {
    // Streaming function should produce the same map as the two-step
    // parseSnomedRelationshipFile + buildParentByChildMap approach.
    [map<string>, int] result = check streamSnomedRelationshipsToParentMap(
        "modules/snomed_to_fhir/tests/resources/sct2_Relationship_Snapshot_INT_20260401.txt"
    );
    map<string> parents = result[0];
    int rowsRead = result[1];

    // rowsRead counts every data row, including inactive and non-is-a rows.
    test:assertEquals(rowsRead, 3);
    // Only the one active is-a row survives into the map.
    test:assertEquals(parents.length(), 1);
    test:assertEquals(parents["123456"], "138875005");
}

@test:Config {}
function testBuildParentByChildMapFirstDestinationWins() {
    // Two active is-a rows for the same child — the first destinationId seen
    // must win. This documents the POC's "one parent only" simplification.
    SnomedRelationshipRow[] rels = [
        {id: "1", effectiveTime: "20260401", active: "1", moduleId: "m", sourceId: "111", destinationId: "222", relationshipGroup: "0", typeId: SNOMED_IS_A_TYPE_ID, characteristicTypeId: "c", modifierId: "d"},
        {id: "2", effectiveTime: "20260401", active: "1", moduleId: "m", sourceId: "111", destinationId: "333", relationshipGroup: "0", typeId: SNOMED_IS_A_TYPE_ID, characteristicTypeId: "c", modifierId: "d"}
    ];

    map<string> parents = buildParentByChildMap(rels);

    test:assertEquals(parents.length(), 1);
    test:assertEquals(parents["111"], "222");
}

@test:Config {}
function testAssembleFsnFallbackForDefinition() {
    // Concept 111 has FSN + no TextDefinition -> definition should fall back to FSN.
    // Concept 222 has FSN + TextDefinition -> TextDefinition wins.
    // Concept 333 has neither FSN nor TextDefinition -> definition stays null.
    SnomedConceptRow[] concepts = [
        {id: "111", effectiveTime: "20260401", active: "1", moduleId: "m", definitionStatusId: "d"},
        {id: "222", effectiveTime: "20260401", active: "1", moduleId: "m", definitionStatusId: "d"},
        {id: "333", effectiveTime: "20260401", active: "1", moduleId: "m", definitionStatusId: "d"}
    ];
    SnomedDescriptionRow[] descriptions = [
        {id: "d1", effectiveTime: "20260401", active: "1", moduleId: "m", conceptId: "111", languageCode: "en", typeId: SNOMED_FSN_TYPE_ID, term: "Concept 111 FSN", caseSignificanceId: "c"},
        {id: "d2", effectiveTime: "20260401", active: "1", moduleId: "m", conceptId: "222", languageCode: "en", typeId: SNOMED_FSN_TYPE_ID, term: "Concept 222 FSN", caseSignificanceId: "c"}
    ];
    SnomedTextDefinitionRow[] textDefinitions = [
        {id: "t1", effectiveTime: "20260401", active: "1", moduleId: "m", conceptId: "222", languageCode: "en", typeId: "900000000000550004", term: "Concept 222 text definition", caseSignificanceId: "c"}
    ];

    SnomedConceptImport[] imports = assembleSnomedConceptImports(concepts, descriptions, textDefinitions);

    test:assertEquals(imports.length(), 3);
    // Order matches concepts input.
    test:assertEquals(imports[0].code, "111");
    test:assertEquals(imports[0].definition, "Concept 111 FSN");
    test:assertEquals(imports[1].code, "222");
    test:assertEquals(imports[1].definition, "Concept 222 text definition");
    test:assertEquals(imports[2].code, "333");
    test:assertEquals(imports[2].definition, ());
}

@test:Config {}
function testSnomedCodeSystemTitleMatchesConformanceDoc() {
    // Section 7 of the conformance doc calls for "SNOMED Clinical Terms".
    test:assertEquals(SNOMED_CODE_SYSTEM_TITLE, "SNOMED Clinical Terms");
    r4:CodeSystem cs = buildSnomedCodeSystemMetadata("20260401");
    test:assertEquals(cs.title, "SNOMED Clinical Terms");
}

@test:Config {}
function testBuildSnomedImportEndToEnd() returns error? {
    SnomedImportBundle bundle = check buildSnomedImport(
        "modules/snomed_to_fhir/tests/resources",
        "20260401"
    );

    test:assertEquals(bundle.conceptsRead, 1);
    test:assertEquals(bundle.descriptionsRead, 2);
    test:assertEquals(bundle.textDefinitionsRead, 0);
    test:assertEquals(bundle.relationshipsRead, 3);
    test:assertEquals(bundle.concepts.length(), 1);
    test:assertEquals(bundle.concepts[0].code, "123456");
    // The end-to-end fixture has one active is-a row (123456 -> 138875005).
    test:assertEquals(bundle.parentByChildSctid.length(), 1);
    test:assertEquals(bundle.parentByChildSctid["123456"], "138875005");
    test:assertEquals(bundle.codeSystemMetadata.version, "20260401");
    test:assertEquals(bundle.codeSystemMetadata.content, r4:CODE_CONTENT_FRAGMENT);
}
