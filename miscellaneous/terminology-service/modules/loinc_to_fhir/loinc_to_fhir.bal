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
import ballerinax/health.fhir.r4;

// Function to read the LOINC CSV file
isolated function readLoincCsv(string path) returns LoincConcept[]|error {
    LoincConcept[]|io:Error content = io:fileReadCsv(path);
    return content;
}

// Function to export the combined CodeSystem resource to a JSON file
isolated function exportCodeSystem(LoincConcept[] concepts, map<map<LoincPartRef>> partIndex, string? 'version, string jsonFilePath) returns error? {
    r4:CodeSystem codeSystem;
    codeSystem = check createCodeSystemResource(concepts, partIndex, 'version);

    check io:fileWriteString(jsonFilePath, codeSystem.toJson().toJsonString());
}

public isolated function convert(string filePath, string? version) returns error? {
    // LoincTable/ and AccessoryFiles/PartFile/ may be at the zip root, or wrapped
    // in the release folder LOINC ships them in (e.g. "Loinc_2.82/") - search for
    // them by name rather than assuming a fixed path.
    string? loincTableDir = check findDirNamed(filePath, "LoincTable");
    if loincTableDir is () {
        return error(string `LoincTable directory not found under ${filePath}`);
    }
    LoincConcept[] loincData = check readLoincCsv(loincTableDir + "/Loinc.csv");

    // The Part File is a separate LOINC download. Optional: properties fall back
    // to their raw CSV text when it isn't present.
    map<map<LoincPartRef>> partIndex = {};
    string? partFileDir = check findDirNamed(filePath, "PartFile");
    if partFileDir is string {
        string primaryPartLinkPath = partFileDir + "/LoincPartLink_Primary.csv";
        boolean primaryExists = check file:test(primaryPartLinkPath, file:EXISTS);
        if primaryExists {
            partIndex = check buildLoincPartIndex(primaryPartLinkPath, partFileDir + "/LoincPartLink_Supplementary.csv");
        }
    }

    check exportCodeSystem(loincData, partIndex, version, filePath + FHIR_LOINC_FILE_NAME);
}

