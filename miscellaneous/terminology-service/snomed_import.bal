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

import terminology_service.snomed_to_fhir as snomed;
import terminology_service.store_h2;

import ballerina/http;
import ballerina/log;
import ballerina/persist;
import ballerinax/health.fhir.r4;

const int SNOMED_INSERT_BATCH_SIZE = 1000;

const int SNOMED_PARENT_LINK_PROGRESS_INTERVAL = 10000;

// Import a SNOMED CT RF2 Snapshot from an extracted directory into the DB.
// Writes one codesystems row (content = fragment, no concepts inlined) and one
// concepts row per active SNOMED concept.
public isolated function importSnomedToDb(string dirPath, string? version) returns snomed:SnomedImportSummary|r4:FHIRError {
    snomed:SnomedImportBundle|error bundle = snomed:buildSnomedImport(dirPath, version);
    if bundle is error {
        return r4:createFHIRError(
                "Failed to build SNOMED import bundle: " + bundle.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = bundle,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }

    byte[]|r4:FHIRError metadataBytes = codeSystemToByte(bundle.codeSystemMetadata);
    if metadataBytes is r4:FHIRError {
        return metadataBytes;
    }

    r4:CodeSystem meta = bundle.codeSystemMetadata;
    store_h2:CodeSystemInsert codeSystemInsert = {
        id: meta.id ?: snomed:SNOMED_CODE_SYSTEM_ID,
        url: meta.url ?: snomed:SNOMED_SYSTEM_URL,
        version: meta.version ?: "",
        name: meta.name ?: snomed:SNOMED_CODE_SYSTEM_NAME,
        title: meta.title ?: snomed:SNOMED_CODE_SYSTEM_TITLE,
        status: meta.status,
        date: meta.date ?: "",
        publisher: meta.publisher ?: snomed:SNOMED_PUBLISHER,
        codeSystem: metadataBytes
    };

    int[]|persist:Error codeSystemResult = sClient->/codesystems.post([codeSystemInsert]);
    if codeSystemResult is persist:Error {
        return r4:createFHIRError(
                "Error while inserting SNOMED CodeSystem row: " + codeSystemResult.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = codeSystemResult,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
    int codeSystemId = codeSystemResult[0];

    // Pass 1: insert concepts (parentConceptId left null)
    int imported = 0;
    map<int> dbIdByCode = {};
    store_h2:ConceptInsert[] batch = [];
    string[] codesInBatch = [];
    foreach snomed:SnomedConceptImport item in bundle.concepts {
        r4:CodeSystemConcept concept = snomed:snomedConceptImportToR4(item);
        byte[]|r4:FHIRError conceptBytes = conceptToByte(concept);
        if conceptBytes is r4:FHIRError {
            log:printError("Skipping SNOMED concept, serialization failed: code=" + item.code + ", " + conceptBytes.message());
            continue;
        }

        store_h2:ConceptInsert conceptInsert = {
            code: item.code,
            display: snomed:truncate191(item.display),
            definition: snomed:truncate191(item.definition),
            concept: conceptBytes,
            parentConceptId: (),
            codesystemCodeSystemId: codeSystemId
        };
        batch.push(conceptInsert);
        codesInBatch.push(item.code);

        if batch.length() >= SNOMED_INSERT_BATCH_SIZE {
            int[]|r4:FHIRError flushedIds = flushConceptBatch(batch);
            if flushedIds is r4:FHIRError {
                return flushedIds;
            }
            recordInsertedIds(dbIdByCode, codesInBatch, flushedIds);
            imported += flushedIds.length();
            batch = [];
            codesInBatch = [];
        }
    }

    if batch.length() > 0 {
        int[]|r4:FHIRError flushedIds = flushConceptBatch(batch);
        if flushedIds is r4:FHIRError {
            return flushedIds;
        }
        recordInsertedIds(dbIdByCode, codesInBatch, flushedIds);
        imported += flushedIds.length();
    }

    // Pass 2: link one parent per concept from active is-a relationships
    int parentsLinked = linkParents(bundle.parentByChildSctid, dbIdByCode);

    return {
        codeSystemId: codeSystemId.toString(),
        system: snomed:SNOMED_SYSTEM_URL,
        version: version ?: "",
        conceptsRead: bundle.conceptsRead,
        conceptsImported: imported,
        descriptionsRead: bundle.descriptionsRead,
        textDefinitionsRead: bundle.textDefinitionsRead,
        relationshipsRead: bundle.relationshipsRead,
        parentsLinked: parentsLinked
    };
}

// Fire-and-forget wrapper around importSnomedToDb for use from the /$upload handler.
public isolated function runSnomedImportAsync(string extractedPath, string? version, string tempDir) returns () {
    log:printInfo("SNOMED import worker started: extractedPath=" + extractedPath);
    snomed:SnomedImportSummary|r4:FHIRError result = importSnomedToDb(extractedPath, version);
    if result is r4:FHIRError {
        log:printError("SNOMED import failed: " + result.message());
    } else {
        log:printInfo(string `SNOMED import complete: conceptsRead=${result.conceptsRead}, conceptsImported=${result.conceptsImported}, descriptionsRead=${result.descriptionsRead}, textDefinitionsRead=${result.textDefinitionsRead}, relationshipsRead=${result.relationshipsRead}, parentsLinked=${result.parentsLinked}, codeSystemId=${result.codeSystemId}`);
    }
    error? cleanup = removeDirectory(tempDir);
    if cleanup is error {
        log:printError("SNOMED cleanup failed for " + tempDir + ": " + cleanup.message());
    }
}

isolated function flushConceptBatch(store_h2:ConceptInsert[] batch) returns int[]|r4:FHIRError {
    int[]|persist:Error result = sClient->/concepts.post(batch);
    if result is persist:Error {
        return r4:createFHIRError(
                "Error while inserting SNOMED concept batch: " + result.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = result,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
    return result;
}

// The persist ->post(batch) contract returns generated ids in the same order
// as the input records, so we zip by index to build code -> dbId.
isolated function recordInsertedIds(map<int> dbIdByCode, string[] codes, int[] ids) {
    int count = codes.length() < ids.length() ? codes.length() : ids.length();
    if codes.length() != ids.length() {
        log:printError(string `SNOMED batch length mismatch: codes=${codes.length()}, ids=${ids.length()}. Some concepts will be unlinkable to parents.`);
    }
    foreach int i in 0 ..< count {
        dbIdByCode[codes[i]] = ids[i];
    }
}

isolated function linkParents(map<string> parentByChildSctid, map<int> dbIdByCode) returns int {
    int linked = 0;
    int skipped = 0;
    foreach [string, string] [childSctid, parentSctid] in parentByChildSctid.entries() {
        int? childDbId = dbIdByCode[childSctid];
        int? parentDbId = dbIdByCode[parentSctid];
        if childDbId is () || parentDbId is () {
            skipped += 1;
            continue;
        }
        store_h2:Concept|persist:Error updated = sClient->/concepts/[childDbId].put({parentConceptId: parentDbId});
        if updated is persist:Error {
            log:printError(string `SNOMED parent link failed for child=${childSctid}: ${updated.message()}`);
            continue;
        }
        linked += 1;
        if linked % SNOMED_PARENT_LINK_PROGRESS_INTERVAL == 0 {
            log:printInfo(string `SNOMED parent linking progress: ${linked} links applied`);
        }
    }
    if skipped > 0 {
        log:printInfo(string `SNOMED parent linking: ${skipped} entries skipped (parent or child not in imported set)`);
    }
    return linked;
}
