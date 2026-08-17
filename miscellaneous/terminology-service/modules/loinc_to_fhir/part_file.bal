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
import ballerina/io;

// LoincPartLink_Primary/Supplementary.csv column indices.
const int PART_LINK_COL_LOINC_NUMBER = 0;
const int PART_LINK_COL_PART_NUMBER = 2;
const int PART_LINK_COL_PART_NAME = 3;
const int PART_LINK_COL_PART_TYPE_NAME = 5;
const int PART_LINK_COL_LINK_TYPE_NAME = 6;
const int PART_LINK_COL_PROPERTY = 7;
const int PART_LINK_COLUMN_COUNT = 8;

// A resolved LOINC Part reference (LP-code + its short name) for one axis of
// one LOINC term.
public type LoincPartRef record {|
    string partNumber;
    string partName;
|};

// Builds a LoincNumber -> {axis: LoincPartRef} index from the Part File's link
// tables, so LOINC properties can emit an LP-code reference (the FHIR-correct
// shape) instead of the raw CSV value. Streamed rather than loaded via
// io:fileReadCsv, since a full LOINC release's Supplementary file can run to
// many millions of rows and only a few are needed per term.
//
// Six axes (COMPONENT, PROPERTY, TIME, SYSTEM, SCALE, METHOD) come from
// Primary.csv's "Primary" rows. CLASS comes from Supplementary.csv's
// "Metadata" rows - it isn't in Primary.csv at all.
isolated function buildLoincPartIndex(string primaryPath, string supplementaryPath) returns map<map<LoincPartRef>>|error {
    map<map<LoincPartRef>> index = {};
    check addPrimaryPartLinks(primaryPath, index);
    check addClassPartLinks(supplementaryPath, index);
    return index;
}

isolated function addPrimaryPartLinks(string path, map<map<LoincPartRef>> index) returns error? {
    stream<string[], io:Error?> rowStream = check io:fileReadCsvAsStream(path);
    boolean first = true;
    record {|string[] value;|}|io:Error? next = rowStream.next();
    while next is record {|string[] value;|} {
        string[] cols = next.value;
        if !first && cols.length() >= PART_LINK_COLUMN_COUNT && cols[PART_LINK_COL_LINK_TYPE_NAME] == "Primary" {
            addPartRef(index, cols);
        }
        first = false;
        next = rowStream.next();
    }
    check rowStream.close();
    if next is io:Error {
        return next;
    }
}

isolated function addClassPartLinks(string path, map<map<LoincPartRef>> index) returns error? {
    stream<string[], io:Error?> rowStream = check io:fileReadCsvAsStream(path);
    boolean first = true;
    record {|string[] value;|}|io:Error? next = rowStream.next();
    while next is record {|string[] value;|} {
        string[] cols = next.value;
        // PartTypeName "CLASS" is reused for two different Property URIs under
        // Metadata - .../property/category (the broader classification) and
        // .../property/CLASS (the actual CLASS value). Only the latter matches
        // what's currently emitted as the CLASS property's raw text.
        if !first && cols.length() >= PART_LINK_COLUMN_COUNT
                && cols[PART_LINK_COL_LINK_TYPE_NAME] == "Metadata" && cols[PART_LINK_COL_PART_TYPE_NAME] == "CLASS"
                && cols[PART_LINK_COL_PROPERTY] == "http://loinc.org/property/CLASS" {
            addPartRef(index, cols);
        }
        first = false;
        next = rowStream.next();
    }
    check rowStream.close();
    if next is io:Error {
        return next;
    }
}

isolated function addPartRef(map<map<LoincPartRef>> index, string[] cols) {
    string loincNumber = cols[PART_LINK_COL_LOINC_NUMBER];
    string partType = cols[PART_LINK_COL_PART_TYPE_NAME];
    map<LoincPartRef> forTerm = index[loincNumber] ?: {};
    forTerm[partType] = {partNumber: cols[PART_LINK_COL_PART_NUMBER], partName: cols[PART_LINK_COL_PART_NAME]};
    index[loincNumber] = forTerm;
}
