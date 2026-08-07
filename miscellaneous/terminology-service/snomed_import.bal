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
import ballerina/sql;
import ballerinax/health.fhir.r4;
import ballerinax/persist.sql as psql;

const int SNOMED_INSERT_BATCH_SIZE = 1000;

const int SNOMED_CLOSURE_PROGRESS_INTERVAL = 100000;
type ClosureRow record {|
    int ancestor;
    int descendant;
    int depth;
|};

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
    string csUrl = meta.url ?: snomed:SNOMED_SYSTEM_URL;
    string csVersion = meta.version ?: "";

    int replaced = check replacePriorLoads(csUrl, csVersion);
    if replaced > 0 {
        log:printInfo(string `SNOMED replace: removed ${replaced} prior load(s) for ${csUrl}|${csVersion}`);
    }

    store_h2:CodeSystemInsert codeSystemInsert = {
        id: meta.id ?: snomed:SNOMED_CODE_SYSTEM_ID,
        url: csUrl,
        version: csVersion,
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

    [int, int]|r4:FHIRError loadResult = loadConceptsAndClosure(bundle, codeSystemId);
    if loadResult is r4:FHIRError {
        error? cleanup = deleteSnomedCodeSystemCascade(codeSystemId);
        if cleanup is error {
            log:printError(string `SNOMED cleanup-on-failure failed for codeSystemId=${codeSystemId}: ${cleanup.message()}`);
        }
        return loadResult;
    }

    return {
        codeSystemId: codeSystemId.toString(),
        system: snomed:SNOMED_SYSTEM_URL,
        version: version ?: "",
        conceptsRead: bundle.conceptsRead,
        conceptsImported: loadResult[0],
        descriptionsRead: bundle.descriptionsRead,
        textDefinitionsRead: bundle.textDefinitionsRead,
        relationshipsRead: bundle.relationshipsRead,
        closureRowsWritten: loadResult[1]
    };
}

isolated function loadConceptsAndClosure(snomed:SnomedImportBundle bundle, int codeSystemId) returns [int, int]|r4:FHIRError {
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

    // Transitive is-a closure: a depth-0 self row per concept plus one row per
    // transitive ancestor that is also in the imported set.
    int closureRowsWritten = check writeClosure(bundle.isaParentsByChild, dbIdByCode, codeSystemId);

    return [imported, closureRowsWritten];
}

isolated function replacePriorLoads(string url, string 'version) returns int|r4:FHIRError {
    sql:ParameterizedQuery q = sql:queryConcat(
            `SELECT `, escapeToQuery("codeSystemId"), ` FROM `, escapeToQuery("codesystems"),
            ` WHERE `, escapeToQuery("url"), ` = ${url} AND `, escapeToQuery("version"), ` = ${'version}`);
    stream<record {|int codeSystemId;|}, persist:Error?> resultStream = sClient->queryNativeSQL(q);
    int[]|error ids = from var row in resultStream
        select row.codeSystemId;
    if ids is error {
        return r4:createFHIRError(
                "Error while finding existing SNOMED loads: " + ids.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = ids,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }

    foreach int id in ids {
        error? del = deleteSnomedCodeSystemCascade(id);
        if del is error {
            return r4:createFHIRError(
                    string `Error while deleting existing SNOMED load codeSystemId=${id}: ${del.message()}`,
                    r4:ERROR,
                    r4:INVALID_REQUIRED,
                    cause = del,
                    httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
        }
    }
    return ids.length();
}

isolated function deleteSnomedCodeSystemCascade(int codeSystemId) returns error? {
    sql:ParameterizedQuery delClosure = sql:queryConcat(
            `DELETE FROM `, escapeToQuery("concept_closure"), ` WHERE `, escapeToQuery("codeSystemId"), ` = ${codeSystemId}`);
    _ = check sClient->executeNativeSQL(delClosure);

    sql:ParameterizedQuery delConcepts = sql:queryConcat(
            `DELETE FROM `, escapeToQuery("concepts"), ` WHERE `, escapeToQuery("codesystemCodeSystemId"), ` = ${codeSystemId}`);
    _ = check sClient->executeNativeSQL(delConcepts);

    sql:ParameterizedQuery delCodeSystem = sql:queryConcat(
            `DELETE FROM `, escapeToQuery("codesystems"), ` WHERE `, escapeToQuery("codeSystemId"), ` = ${codeSystemId}`);
    _ = check sClient->executeNativeSQL(delCodeSystem);
}

isolated function writeClosure(map<string[]> isaParentsByChild, map<int> dbIdByCode, int codeSystemId) returns int|r4:FHIRError {
    int written = 0;
    ClosureRow[] batch = [];

    foreach [string, int] [code, childDbId] in dbIdByCode.entries() {
        // Depth-0 self row: a concept is its own ancestor at depth 0.
        batch.push({ancestor: childDbId, descendant: childDbId, depth: 0});

        map<int> ancestorDepths = snomed:computeAncestorDepths(code, isaParentsByChild);
        foreach [string, int] [ancestorSctid, depth] in ancestorDepths.entries() {
            int? ancestorDbId = dbIdByCode[ancestorSctid];
            if ancestorDbId is int {
                batch.push({ancestor: ancestorDbId, descendant: childDbId, depth: depth});
            }
        }

        if batch.length() >= SNOMED_INSERT_BATCH_SIZE {
            int|r4:FHIRError flushed = flushClosureBatch(batch, codeSystemId);
            if flushed is r4:FHIRError {
                return flushed;
            }
            written += flushed;
            batch = [];
            if written % SNOMED_CLOSURE_PROGRESS_INTERVAL < SNOMED_INSERT_BATCH_SIZE {
                log:printInfo(string `SNOMED closure progress: ${written} rows written`);
            }
        }
    }

    if batch.length() > 0 {
        int|r4:FHIRError flushed = flushClosureBatch(batch, codeSystemId);
        if flushed is r4:FHIRError {
            return flushed;
        }
        written += flushed;
    }

    return written;
}

isolated function flushClosureBatch(ClosureRow[] rows, int codeSystemId) returns int|r4:FHIRError {
    if rows.length() == 0 {
        return 0;
    }

    string head = string `INSERT INTO ${escape("concept_closure")} (${escape("ancestorConceptId")}, ${escape("descendantConceptId")}, ${escape("depth")}, ${escape("codeSystemId")}) VALUES `;

    sql:ParameterizedQuery[] fragments = [stringToParameterizedQuery(head)];
    boolean first = true;
    foreach ClosureRow row in rows {
        if !first {
            fragments.push(`, `);
        }
        fragments.push(`(${row.ancestor}, ${row.descendant}, ${row.depth}, ${codeSystemId})`);
        first = false;
    }

    sql:ParameterizedQuery query = sql:queryConcat(...fragments);
    psql:ExecutionResult|persist:Error result = sClient->executeNativeSQL(query);
    if result is persist:Error {
        return r4:createFHIRError(
                "Error while inserting SNOMED closure batch: " + result.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = result,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
    return rows.length();
}

public isolated function runSnomedImportAsync(string extractedPath, string? version, string tempDir) returns () {
    log:printInfo("SNOMED import worker started: extractedPath=" + extractedPath);
    snomed:SnomedImportSummary|r4:FHIRError result = importSnomedToDb(extractedPath, version);
    if result is r4:FHIRError {
        log:printError("SNOMED import failed: " + result.message());
    } else {
        log:printInfo(string `SNOMED import complete: conceptsRead=${result.conceptsRead}, conceptsImported=${result.conceptsImported}, descriptionsRead=${result.descriptionsRead}, textDefinitionsRead=${result.textDefinitionsRead}, relationshipsRead=${result.relationshipsRead}, closureRowsWritten=${result.closureRowsWritten}, codeSystemId=${result.codeSystemId}`);
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

isolated function recordInsertedIds(map<int> dbIdByCode, string[] codes, int[] ids) {
    int count = codes.length() < ids.length() ? codes.length() : ids.length();
    if codes.length() != ids.length() {
        log:printError(string `SNOMED batch length mismatch: codes=${codes.length()}, ids=${ids.length()}. Some concepts will be unlinkable to parents.`);
    }
    foreach int i in 0 ..< count {
        dbIdByCode[codes[i]] = ids[i];
    }
}

