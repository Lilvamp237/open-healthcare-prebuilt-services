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
import ballerina/http;
import ballerina/persist;
import ballerina/sql;
import ballerinax/health.fhir.r4;
import ballerinax/persist.sql as psql;

type ConceptMapRow record {|
    int conceptMapId;
    string id;
    string? url;
    string? 'version;
    string? name;
    string? title;
    string status;
    string? sourceUri;
    string? targetUri;
    byte[] conceptMap;
|};

// ConceptMap.source[x] and target[x] are choice types (uri or canonical) -
// either can carry the ValueSet scope findConceptMaps searches by.
isolated function conceptMapSourceUri(r4:ConceptMap cm) returns string? {
    return cm.sourceUri ?: cm.sourceCanonical;
}

isolated function conceptMapTargetUri(r4:ConceptMap cm) returns string? {
    return cm.targetUri ?: cm.targetCanonical;
}

// Backs TerminologySource.addConceptMap. Mirrors addCodeSystem/addValueSet's
// shape - stores the full resource as a blob plus queryable columns.
isolated function storeConceptMap(r4:ConceptMap conceptMap) returns r4:FHIRError? {
    byte[]|r4:FHIRError bytes = conceptMapToByte(conceptMap);
    if bytes is r4:FHIRError {
        return bytes;
    }

    sql:ParameterizedQuery query = sql:queryConcat(
            `INSERT INTO `, escapeToQuery("conceptmaps"),
            ` (`, escapeToQuery("id"), `, `, escapeToQuery("url"), `, `, escapeToQuery("version"), `, `,
            escapeToQuery("name"), `, `, escapeToQuery("title"), `, `, escapeToQuery("status"), `, `,
            escapeToQuery("sourceUri"), `, `, escapeToQuery("targetUri"), `, `, escapeToQuery("conceptMap"), `)`,
            ` VALUES (${conceptMap.id ?: ""}, ${conceptMap.url}, ${conceptMap.'version}, ${conceptMap.name}, `,
            `${conceptMap.title}, ${conceptMap.status}, ${conceptMapSourceUri(conceptMap)}, `,
            `${conceptMapTargetUri(conceptMap)}, ${bytes})`);
    psql:ExecutionResult|persist:Error result = sClient->executeNativeSQL(query);
    if result is persist:Error {
        return r4:createFHIRError(
                "Error while adding ConceptMap, " + result.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = result,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
}

// Backs TerminologySource.findConceptMaps: the terminology library's translate()
// calls this to find candidate ConceptMaps for a given source (and optionally
// target) ValueSet scope, then does the actual code matching itself.
isolated function findStoredConceptMaps(r4:uri sourceValueSetUri, r4:uri? targetValueSetUri) returns r4:ConceptMap[]|r4:FHIRError {
    sql:ParameterizedQuery query;
    if targetValueSetUri is r4:uri {
        query = sql:queryConcat(
                `SELECT * FROM `, escapeToQuery("conceptmaps"),
                ` WHERE `, escapeToQuery("sourceUri"), ` = ${sourceValueSetUri}`,
                ` AND `, escapeToQuery("targetUri"), ` = ${targetValueSetUri}`);
    } else {
        query = sql:queryConcat(
                `SELECT * FROM `, escapeToQuery("conceptmaps"),
                ` WHERE `, escapeToQuery("sourceUri"), ` = ${sourceValueSetUri}`);
    }
    return queryStoredConceptMaps(query);
}

// Backs TerminologySource.getConceptMap: direct lookup by canonical url (+
// optional version).
isolated function getStoredConceptMapByUrl(r4:uri url, string? conceptMapVersion) returns r4:ConceptMap|r4:FHIRError {
    sql:ParameterizedQuery query;
    if conceptMapVersion is string {
        query = sql:queryConcat(
                `SELECT * FROM `, escapeToQuery("conceptmaps"),
                ` WHERE `, escapeToQuery("url"), ` = ${url} AND `, escapeToQuery("version"), ` = ${conceptMapVersion}`);
    } else {
        query = sql:queryConcat(
                `SELECT * FROM `, escapeToQuery("conceptmaps"), ` WHERE `, escapeToQuery("url"), ` = ${url}`);
    }
    r4:ConceptMap[]|r4:FHIRError results = queryStoredConceptMaps(query);
    if results is r4:FHIRError {
        return results;
    }
    if results.length() == 0 {
        return r4:createFHIRError(
                "ConceptMap not found: " + url,
                r4:ERROR,
                r4:PROCESSING_NOT_FOUND,
                cause = error("No ConceptMap found for url " + url),
                httpStatusCode = http:STATUS_NOT_FOUND);
    }
    return results[0];
}

// Backs TerminologySource.isConceptMapExist.
isolated function storedConceptMapExists(r4:uri url, string conceptMapVersion) returns boolean {
    sql:ParameterizedQuery query = sql:queryConcat(
            `SELECT 1 FROM `, escapeToQuery("conceptmaps"),
            ` WHERE `, escapeToQuery("url"), ` = ${url} AND `, escapeToQuery("version"), ` = ${conceptMapVersion} LIMIT 1`);
    stream<record {}, persist:Error?> resultStream = sClient->queryNativeSQL(query);
    record {}[]|error rows = from record {} r in resultStream
        select r;
    return rows is error ? false : rows.length() > 0;
}

// Backs TerminologySource.searchConceptMap. Supports the common search
// parameters (_id, url, name, status); returns everything if none are given.
isolated function searchStoredConceptMaps(map<r4:RequestSearchParameter[]> params, int? offset, int? count) returns r4:ConceptMap[]|r4:FHIRError {
    sql:ParameterizedQuery[] conditions = [];

    r4:RequestSearchParameter[]? idParam = params["_id"];
    if idParam is r4:RequestSearchParameter[] && idParam.length() > 0 {
        conditions.push(sql:queryConcat(escapeToQuery("id"), ` = ${idParam[0].value}`));
    }
    r4:RequestSearchParameter[]? urlParam = params["url"];
    if urlParam is r4:RequestSearchParameter[] && urlParam.length() > 0 {
        conditions.push(sql:queryConcat(escapeToQuery("url"), ` = ${urlParam[0].value}`));
    }
    r4:RequestSearchParameter[]? nameParam = params["name"];
    if nameParam is r4:RequestSearchParameter[] && nameParam.length() > 0 {
        conditions.push(sql:queryConcat(escapeToQuery("name"), ` = ${nameParam[0].value}`));
    }
    r4:RequestSearchParameter[]? statusParam = params["status"];
    if statusParam is r4:RequestSearchParameter[] && statusParam.length() > 0 {
        conditions.push(sql:queryConcat(escapeToQuery("status"), ` = ${statusParam[0].value}`));
    }

    sql:ParameterizedQuery query = sql:queryConcat(`SELECT * FROM `, escapeToQuery("conceptmaps"));
    if conditions.length() > 0 {
        sql:ParameterizedQuery[] whereFragments = [` WHERE `];
        boolean first = true;
        foreach var cond in conditions {
            if !first {
                whereFragments.push(` AND `);
            }
            whereFragments.push(cond);
            first = false;
        }
        query = sql:queryConcat(query, sql:queryConcat(...whereFragments));
    }
    if count is int {
        query = sql:queryConcat(query, getLimitClause(count, offset ?: 0));
    }

    return queryStoredConceptMaps(query);
}

// Shared by all the lookup/search functions above: runs the query, decodes each
// row's stored blob back into a ConceptMap, and silently skips any row that
// fails to decode rather than failing the whole call.
isolated function queryStoredConceptMaps(sql:ParameterizedQuery query) returns r4:ConceptMap[]|r4:FHIRError {
    stream<ConceptMapRow, persist:Error?> resultStream = sClient->queryNativeSQL(query);
    ConceptMapRow[]|error rows = from ConceptMapRow row in resultStream
        select row;
    if rows is error {
        return r4:createFHIRError(
                "Error while searching for ConceptMap: " + rows.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = rows,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }

    r4:ConceptMap[] results = [];
    foreach ConceptMapRow row in rows {
        r4:ConceptMap|error cm = byteToConceptMap(row.conceptMap);
        if cm is r4:ConceptMap {
            results.push(cm);
        }
    }
    return results;
}

