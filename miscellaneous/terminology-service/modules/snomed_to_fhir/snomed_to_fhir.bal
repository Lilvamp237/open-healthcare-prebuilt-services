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

// Function to read an RF2 Snapshot release directory and produce the inputs the DB layer needs to import SNOMED CT
public isolated function buildSnomedImport(string dirPath, string? version) returns SnomedImportBundle|error {
    string conceptFilePath = check findRf2File(dirPath, RF2_CONCEPT_PREFIX);
    string descriptionFilePath = check findRf2File(dirPath, RF2_DESCRIPTION_PREFIX);
    string relationshipFilePath = check findRf2File(dirPath, RF2_RELATIONSHIP_PREFIX);

    [map<ConceptDescriptions>, int] descResult = check streamDescriptionIndex(descriptionFilePath);
    map<ConceptDescriptions> descIndex = descResult[0];
    int descriptionsRead = descResult[1];

    // TextDefinition is optional
    map<string> defIndex = {};
    int textDefinitionsRead = 0;
    string|error textDefinitionFilePath = findRf2File(dirPath, RF2_TEXT_DEFINITION_PREFIX);
    if textDefinitionFilePath is string {
        boolean exists = check file:test(textDefinitionFilePath, file:EXISTS);
        if exists {
            [map<string>, int] defResult = check streamTextDefinitionIndex(textDefinitionFilePath);
            defIndex = defResult[0];
            textDefinitionsRead = defResult[1];
        }
    }

    // Stream concepts
    [SnomedConceptImport[], int] conceptResult = check streamConceptImports(conceptFilePath, descIndex, defIndex);
    SnomedConceptImport[] importRecords = conceptResult[0];
    int conceptsRead = conceptResult[1];

    descIndex = {};
    defIndex = {};

    [map<string>, int] parentResult = check streamSnomedRelationshipsToParentMap(relationshipFilePath);

    return {
        codeSystemMetadata: buildSnomedCodeSystemMetadata(version),
        concepts: importRecords,
        parentByChildSctid: parentResult[0],
        conceptsRead: conceptsRead,
        descriptionsRead: descriptionsRead,
        textDefinitionsRead: textDefinitionsRead,
        relationshipsRead: parentResult[1]
    };
}
