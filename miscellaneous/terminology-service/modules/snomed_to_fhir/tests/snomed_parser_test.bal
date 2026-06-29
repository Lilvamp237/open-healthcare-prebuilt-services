import ballerina/test;

@test:Config {}
function testParseSnomedConceptFile() returns error? {
    SnomedConceptRow[] concepts = check parseSnomedConceptFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Concept_Snapshot_INT_20260401.txt"
    );

    test:assertEquals(concepts.length(), 1);
    test:assertEquals(concepts[0].id, "123456");
    test:assertEquals(concepts[0].effectiveTime, "20260401");
    test:assertEquals(concepts[0].active, "1");
    test:assertEquals(concepts[0].moduleId, "900000000000207008");
    test:assertEquals(concepts[0].definitionStatusId, "900000000000074008");
}

@test:Config {}
function testParseSnomedDescriptionFile() returns error? {
    SnomedDescriptionRow[] descriptions = check parseSnomedDescriptionFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Description_Snapshot-en_INT_20260401.txt"
    );

    test:assertEquals(descriptions.length(), 2);

    test:assertEquals(descriptions[0].conceptId, "123456");
    test:assertEquals(descriptions[0].typeId, SNOMED_FSN_TYPE_ID);
    test:assertEquals(descriptions[0].term, "Test concept (finding)");

    test:assertEquals(descriptions[1].conceptId, "123456");
    test:assertEquals(descriptions[1].typeId, SNOMED_SYNONYM_TYPE_ID);
    test:assertEquals(descriptions[1].term, "Test concept");
}

@test:Config {}
function testActiveDescriptionFiltering() returns error? {
    SnomedDescriptionRow[] descriptions = check parseSnomedDescriptionFile(
        "modules/snomed_to_fhir/tests/resources/sct2_Description_Snapshot-en_INT_20260401.txt"
    );

    SnomedDescriptionRow[] activeDescriptions = getActiveDescriptions(descriptions);

    test:assertEquals(activeDescriptions.length(), 2);
    test:assertTrue(isFsn(activeDescriptions[0]));
    test:assertTrue(isSynonym(activeDescriptions[1]));
}