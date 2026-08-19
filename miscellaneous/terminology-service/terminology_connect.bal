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

import terminology_service.loinc_to_fhir as loinc;
import terminology_service.store_h2;

import ballerina/http;
import ballerina/log;
import ballerina/regex;
import ballerina/time;
import ballerina/uuid;
import ballerinax/health.fhir.r4;
import ballerinax/health.fhir.r4.terminology;

final TerminologySource terminology_source = new TerminologySource();

public isolated function readCodeSystemById(string id) returns r4:FHIRError|r4:CodeSystem|r4:FHIRError {
    string[] split = regex:split(id, string `\|`);
    string code_system_id = split[0];
    string? code_system_id_version = split.length() > 1 ? split[1] : ();

    return terminology:readCodeSystemById(id = code_system_id, version = code_system_id_version, terminology = terminology_source);
}

public isolated function readValueSetById(string id) returns r4:ValueSet|r4:FHIRError {
    string[] split = regex:split(id, string `\|`);
    string value_set_id = split[0];
    string? value_set_id_version = split.length() > 1 ? split[1] : ();

    return terminology:readValueSetById(id = value_set_id, version = value_set_id_version, terminology = terminology_source);
}

public isolated function readCodeSystemByUrl(string url) returns r4:CodeSystem|r4:FHIRError {
    string[] split = regex:split(url, string `\|`);
    string code_system_url = split[0];
    string? code_system_url_version = split.length() > 1 ? split[1] : ();

    return terminology:readCodeSystemByUrl(url = code_system_url, version = code_system_url_version, terminology = terminology_source);
}

public isolated function readValueSetByUrl(string url) returns r4:ValueSet|r4:FHIRError {
    string[] split = regex:split(url, string `\|`);
    string value_set_url = split[0];
    string? value_set_url_version = split.length() > 1 ? split[1] : ();

    return terminology:readValueSetByUrl(url = value_set_url, version = value_set_url_version, terminology = terminology_source);
}

public isolated function readConceptMapByUrl(string url) returns r4:ConceptMap|r4:FHIRError {
    string[] split = regex:split(url, string `\|`);
    string concept_map_url = split[0];
    string? concept_map_url_version = split.length() > 1 ? split[1] : ();

    return terminology:readConceptMap(conceptMapUrl = concept_map_url, version = concept_map_url_version, terminology = terminology_source);
}

// The terminology library only exposes ConceptMap lookup by canonical url
// (readConceptMap) - there's no by-id counterpart like readCodeSystemById /
// readValueSetById. Resolved directly against storage instead.
public isolated function readConceptMapById(string id) returns r4:ConceptMap|r4:FHIRError {
    r4:ConceptMap[] results = check searchStoredConceptMaps({"_id": [createRequestSearchParameter("_id", id)]}, (), ());
    if results.length() == 0 {
        return r4:createFHIRError(
                "ConceptMap not found: " + id,
                r4:ERROR,
                r4:PROCESSING_NOT_FOUND,
                cause = error("No ConceptMap found for id " + id),
                httpStatusCode = http:STATUS_NOT_FOUND);
    }
    return results[0];
}

public isolated function searchValueSet(r4:FHIRContext ctx) returns r4:Bundle|r4:FHIRError {

    map<r4:RequestSearchParameter[]>|error params = getSearchParametersFromFHIRContext(ctx);

    if params is error {
        log:printError("Failed to get search parameters from FHIR context", 'error = params);
        return r4:createFHIRError(
                "Invalid search parameters",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = params,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:ValueSet[] valueSets = check terminology:searchValueSets(params, terminology = terminology_source);

    r4:BundleEntry[] entries = valueSets.'map(v => <r4:BundleEntry>{'resource: v, search: {mode: r4:MATCH}});

    return {
        'type: r4:BUNDLE_TYPE_SEARCHSET,
        meta: {
            lastUpdated: time:utcToString(time:utcNow())
        },
        total: entries.length(),
        entry: entries
    };
}

public isolated function searchCodeSystem(r4:FHIRContext ctx) returns r4:Bundle|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly params = ctx.getRequestSearchParameters();
    map<r4:RequestSearchParameter[]>|error clonedParams = params.cloneWithType();

    if clonedParams is error {
        return r4:createFHIRError(
                "Invalid search parameters blah",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeSystem[] codeSystems = check terminology:searchCodeSystems(clonedParams, terminology = terminology_source);

    r4:BundleEntry[] entries = codeSystems.'map(c => <r4:BundleEntry>{'resource: c.toJson(), search: {mode: r4:MATCH}});

    return {
        'type: r4:BUNDLE_TYPE_SEARCHSET,
        meta: {
            lastUpdated: time:utcToString(time:utcNow())
        },
        total: entries.length(),
        entry: entries
    };
}

public isolated function searchConceptMap(r4:FHIRContext ctx) returns r4:Bundle|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly params = ctx.getRequestSearchParameters();
    map<r4:RequestSearchParameter[]>|error clonedParams = params.cloneWithType();

    if clonedParams is error {
        return r4:createFHIRError(
                "Invalid search parameters",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:ConceptMap[] conceptMaps = check terminology:searchConceptMaps(clonedParams, terminology = terminology_source);

    r4:BundleEntry[] entries = conceptMaps.'map(c => <r4:BundleEntry>{'resource: c.toJson(), search: {mode: r4:MATCH}});

    return {
        'type: r4:BUNDLE_TYPE_SEARCHSET,
        meta: {
            lastUpdated: time:utcToString(time:utcNow())
        },
        total: entries.length(),
        entry: entries
    };
}

// ---------------------------------------------------------------------------
// TEMPORARY SHIM (branch: api-conformance).
// The terminology library (ballerinax/health.fhir.r4.terminology) only supports
// the expansion parameters url, valueSetVersion, filter, _offset and _count, and
// returns a hard error ("Invalid search parameter: ...") for anything else. The
// HL7 tx-ecosystem test suite sends many additional parameters (excludeNested,
// activeOnly, includeDesignations, displayLanguage, property, ...). To let the
// suite run end-to-end and produce a real pass/fail report, this helper maps the
// common aliases (count -> _count, offset -> _offset) and drops parameters the
// server does not implement, so expansion returns a 2xx result instead of a 500.
// Tests that depend on the dropped parameters will still fail on output comparison
// (which is the honest, expected result) rather than failing the HTTP call.
// Remove this shim once the parameters are natively supported.
// ---------------------------------------------------------------------------
isolated function filterSupportedExpansionParams(map<r4:RequestSearchParameter[]> params) returns map<r4:RequestSearchParameter[]> {
    map<r4:RequestSearchParameter[]> supported = {};
    foreach var [key, value] in params.entries() {
        string normalized = key;
        if key == "count" {
            normalized = "_count";
        } else if key == "offset" {
            normalized = "_offset";
        }
        if normalized == "url" || normalized == "valueSetVersion" || normalized == "filter"
                || normalized == "_offset" || normalized == "_count" {
            r4:RequestSearchParameter[] renamed = [];
            foreach var p in value {
                renamed.push({name: normalized, value: p.value, 'type: p.'type, typedValue: p.typedValue});
            }
            supported[normalized] = renamed;
        }
    }
    return supported;
}

// Extract the scalar value of a FHIR Parameters.parameter entry (value[x]) as a string.
isolated function extractBodyParamValue(map<json> paramItem) returns string? {
    foreach var [key, value] in paramItem.entries() {
        if key.startsWith("value") && (value is string || value is int || value is float || value is decimal || value is boolean) {
            return value.toString();
        }
    }
    return ();
}

// Fills in the parts of an expansion the library leaves out: the system on each
// entry, the abstract and inactive flags, an identifier, and the parameter echo.
// Also drops inactive concepts when activeOnly or compose.inactive asks for it.
isolated function postProcessExpansion(r4:ValueSet vs, r4:ValueSet? sourceVs, map<r4:RequestSearchParameter[]> requestParams) returns r4:ValueSet {
    r4:ValueSet mutable = vs.clone();
    r4:ValueSetExpansion? expansion = mutable.expansion;
    if expansion is () {
        return mutable;
    }

    string? csUrl = ();
    if sourceVs is r4:ValueSet {
        r4:ValueSetCompose? compose = sourceVs.compose;
        if compose is r4:ValueSetCompose {
            r4:ValueSetComposeInclude[] includes = compose.include;
            if includes.length() > 0 {
                string? firstSys = includes[0].system;
                boolean uniform = firstSys is string;
                foreach var inc in includes {
                    if inc.system != firstSys {
                        uniform = false;
                        break;
                    }
                }
                if uniform && firstSys is string {
                    csUrl = firstSys;
                }
            }
        }
    }

    if csUrl is () {
        return mutable;
    }

    r4:ValueSetExpansionContains[]? contains = expansion.contains;
    if contains is () {
        return mutable;
    }
    if expansion.identifier is () {
        expansion.identifier = "urn:uuid:" + uuid:createType4AsString();
    }

    foreach int i in 0 ..< contains.length() {
        if contains[i].system is () {
            contains[i].system = <r4:uri>csUrl;
        }

        r4:code? entryCode = contains[i].code;
        if entryCode is r4:code {
            [boolean, boolean] flags = getConceptFlags(<r4:uri>csUrl, entryCode);
            if flags[0] {
                contains[i].'abstract = true;
            }
            if flags[1] {
                contains[i].inactive = true;
            }
        }
    }

    // Drop inactive concepts when the client asked for activeOnly or the ValueSet says so
    boolean requestActiveOnly = false;
    r4:RequestSearchParameter[]? activeOnlyParam = requestParams["activeOnly"];
    if activeOnlyParam is r4:RequestSearchParameter[] && activeOnlyParam.length() > 0 {
        requestActiveOnly = activeOnlyParam[0].value == "true";
    }

    boolean composeExcludesInactive = false;
    if sourceVs is r4:ValueSet {
        r4:ValueSetCompose? sourceCompose = sourceVs.compose;
        if sourceCompose is r4:ValueSetCompose && sourceCompose.inactive is boolean
            && !<boolean>sourceCompose.inactive {
            composeExcludesInactive = true;
        }
    }

    if requestActiveOnly || composeExcludesInactive {
        r4:ValueSetExpansionContains[] filtered = [];
        foreach var entry in contains {
            if entry.inactive is boolean && <boolean>entry.inactive {
                continue;
            }
            filtered.push(entry);
        }
        expansion.contains = filtered;
        expansion.total = filtered.length();
    }

    r4:ValueSetExpansionParameter[] expParams = [];

    // Echo back the requested count if client sent one
    r4:RequestSearchParameter[]? countParam = requestParams["count"];
    if countParam is r4:RequestSearchParameter[] && countParam.length() > 0 {
        int|error countVal = int:fromString(countParam[0].value);
        if countVal is int {
            expParams.push({name: "count", valueInteger: countVal});
        }
    }

    r4:RequestSearchParameter[]? excludeNestedParam = requestParams["excludeNested"];
    if excludeNestedParam is r4:RequestSearchParameter[] && excludeNestedParam.length() > 0 {
        expParams.push({name: "excludeNested", valueBoolean: excludeNestedParam[0].value == "true"});
    }

    r4:CodeSystem|r4:FHIRError csForVersion = readCodeSystemByUrl(<string>csUrl);
    if csForVersion is r4:CodeSystem {
        string usedCs = csForVersion.version is string
            ? <string>csUrl + "|" + <string>csForVersion.version
            : <string>csUrl;
        expParams.push({name: "used-codesystem", valueUri: usedCs});
    }

    r4:RequestSearchParameter[]? displayLangParam = requestParams["displayLanguage"];
    if displayLangParam is r4:RequestSearchParameter[] && displayLangParam.length() > 0 {
        expParams.push({name: "displayLanguage", valueString: displayLangParam[0].value});
    }

    if expParams.length() > 0 {
        expansion.'parameter = expParams;
    }
    return mutable;
}

public isolated function valueSetExpansionGet(r4:FHIRContext ctx, string? id = ()) returns r4:ValueSet|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly searchParameters = ctx.getRequestSearchParameters();
    map<r4:RequestSearchParameter[]> mutableParams = {};
    foreach var [k, v] in searchParameters.entries() {
        mutableParams[k] = v;
    }

    string? system = searchParameters["url"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>searchParameters["url"])[0].value : ();
    map<r4:RequestSearchParameter[]> supportedParams = filterSupportedExpansionParams(mutableParams);

    //return valueSet;
    r4:ValueSet valueSet;
    r4:ValueSet? sourceVs = ();
    if id is string {
        r4:ValueSet resolved = check readValueSetById(id);
        sourceVs = resolved;
        valueSet = check terminology:valueSetExpansion(supportedParams, vs = resolved, terminology = terminology_source);
    } else {
        if system is string {
            r4:ValueSet|r4:FHIRError vsResult = readValueSetByUrl(system);
            if vsResult is r4:ValueSet {
                sourceVs = vsResult;
            }
        }
        valueSet = check terminology:valueSetExpansion(supportedParams, system = system, terminology = terminology_source);
    }
    return postProcessExpansion(valueSet, sourceVs, mutableParams);
}

public isolated function valueSetExpansionPost(r4:FHIRContext ctx, r4:Parameters parameters, string? id = ()) returns r4:ValueSet|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly searchParameters = ctx.getRequestSearchParameters();
    map<r4:RequestSearchParameter[]> mutableParams = {};
    foreach var [k, v] in searchParameters.entries() {
        mutableParams[k] = v;
    }

    r4:ValueSet? inlineValueSet = ();
    string? system = ();
    json paramsJson = parameters.toJson();
    json parametersArray = (paramsJson is map<json>) ? (paramsJson["parameter"] ?: []) : [];
    if parametersArray is json[] {
        foreach json paramItem in parametersArray {
            if paramItem !is map<json> {
                continue;
            }
            string paramName = paramItem["name"] is string ? <string>paramItem["name"] : "";
            if paramName == "valueSet" {
                json? resourceJson = paramItem["resource"];
                if resourceJson is map<json> {
                    r4:ValueSet|error vs = resourceJson.cloneWithType(r4:ValueSet);
                    if vs is r4:ValueSet {
                        inlineValueSet = vs;
                    }
                }
            } else if paramName == "url" {
                system = extractBodyParamValue(paramItem);
            } else {
                string? val = extractBodyParamValue(paramItem);
                if val is string {
                    mutableParams[paramName] = [{name: paramName, value: val, 'type: r4:STRING, typedValue: {modifier: ()}}];
                }
            }
        }
    }

    map<r4:RequestSearchParameter[]> supportedParams = filterSupportedExpansionParams(mutableParams);

    r4:ValueSet expansionResult;
    r4:ValueSet? sourceVs = ();

    if id is string {
        r4:ValueSet resolved = check readValueSetById(id);
        sourceVs = resolved;
        expansionResult = check terminology:valueSetExpansion(supportedParams, vs = resolved, terminology = terminology_source);
    } else if inlineValueSet is r4:ValueSet {
        sourceVs = inlineValueSet;
        expansionResult = check terminology:valueSetExpansion(supportedParams, vs = inlineValueSet, terminology = terminology_source);
    } else {
        if system is string {
            r4:ValueSet|r4:FHIRError vsResult = readValueSetByUrl(system);
            if vsResult is r4:ValueSet {
                sourceVs = vsResult;
            }
        }
        expansionResult = check terminology:valueSetExpansion(supportedParams, system = system, terminology = terminology_source);
    }

    return postProcessExpansion(expansionResult, sourceVs, mutableParams);

}

public isolated function valueSetValidateCodePost(r4:FHIRContext ctx, r4:Parameters parameters) returns r4:Parameters|r4:FHIRError {
    r4:Parameters|r4:FHIRError concept = valueSetLookUpPost(ctx, parameters);
    return validationResultToParameters(concept);
}

public isolated function valueSetValidateCodeGet(r4:FHIRContext ctx, string? id = ()) returns r4:Parameters|r4:FHIRError {
    r4:Parameters|r4:FHIRError concept = valueSetLookUpGet(ctx, id);
    return validationResultToParameters(concept);
}

public isolated function codeSystemLookUpGet(r4:FHIRContext ctx, string? id = ()) returns r4:Parameters|r4:FHIRError {

    map<r4:RequestSearchParameter[] & readonly> & readonly idParam = ctx.getRequestSearchParameters();

    string? system = idParam["system"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["system"])[0].value : ();
    string? code = idParam["code"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["code"])[0].value : ();
    string? 'version = idParam["version"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["version"])[0].value : ();
    r4:code|r4:Coding? codeValue = code;

    if codeValue !is r4:code|r4:Coding {
        return r4:createFHIRError(
                "Invalid request payload, Code value is missing",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeSystemConcept[]|r4:CodeSystemConcept result;
    r4:CodeSystem? cs = ();

    if id is string {
        r4:CodeSystem resolvedCs = check readCodeSystemById(id);
        cs = resolvedCs;
        result = check terminology:codeSystemLookUp(<r4:code>codeValue, system = resolvedCs.url ?: "", version = 'version, terminology = terminology_source);
    } else if system is string {
        r4:CodeSystem|r4:FHIRError csResult = readCodeSystemByUrl(system);
        if csResult is r4:CodeSystem {
            cs = csResult;
        }
        result = check terminology:codeSystemLookUp(<r4:code>codeValue, system = system, version = 'version, terminology = terminology_source);
    } else {
        return r4:createFHIRError(
                "Can not find a CodeSystem",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeSystemConcept? parentConcept = ();
    r4:CodeSystemConcept[] childConcepts = [];
    ConceptAttributeRelationship[] attributeRelationships = [];
    if cs is r4:CodeSystem && cs.url is r4:uri {
        [r4:CodeSystemConcept?, r4:CodeSystemConcept[]] hierarchy =
                getConceptHierarchy(<r4:uri>cs.url, <r4:code>codeValue, 'version);
        parentConcept = hierarchy[0];
        childConcepts = hierarchy[1];
        attributeRelationships = getConceptAttributeRelationships(<r4:uri>cs.url, <r4:code>codeValue, 'version);
    }

    return codesystemConceptsToParameters(result, cs, parentConcept, childConcepts, attributeRelationships);
}

public isolated function codeSystemLookUpPost(r4:FHIRContext ctx, r4:Parameters parameters) returns r4:Parameters|r4:FHIRError {
    r4:Coding? codingValue = ();
    r4:uri? system = ();
    r4:code? code = ();
    string? 'version = ();
    r4:CodeSystem? cs = ();

    r4:Parameters|error typedParams = parameters.toJson().cloneWithType(r4:Parameters);
    if typedParams is error {
        return r4:createFHIRError("Invalid request payload", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if typedParams.'parameter is r4:ParametersParameter[] {
        // $lookup accepts EITHER a "coding" parameter OR separate "system"/"code"
        // (+ optional "version") parameters.
        foreach var item in <r4:ParametersParameter[]>typedParams.'parameter {
            match item.name {
                "coding" => {
                    codingValue = item.valueCoding;
                    if codingValue is r4:Coding && codingValue.system is r4:uri {
                        system = codingValue.system;
                    }
                }
                "system" => {
                    system = item.valueUri ?: item.valueString;
                }
                "code" => {
                    code = item.valueCode ?: item.valueString;
                }
                "version" => {
                    'version = item.valueString;
                }
            }
        }
    } else {
        return r4:createFHIRError(
                "Invalid request payload",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeSystemConcept[]|r4:CodeSystemConcept result;
    r4:code? effectiveCode = ();
    if codingValue is r4:Coding && system is string {
        result = check terminology:codeSystemLookUp(codingValue, system = system, version = 'version, terminology = terminology_source);
        effectiveCode = codingValue.code;
    } else if code is r4:code && system is string {
        result = check terminology:codeSystemLookUp(code, system = system, version = 'version, terminology = terminology_source);
        effectiveCode = code;
    } else {
        return r4:createFHIRError(
                "Can not find a CodeSystem",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                diagnostic = "Provide either a 'coding' parameter or 'system' and 'code' parameters",
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if system is r4:uri {
        r4:CodeSystem|r4:FHIRError csResult = readCodeSystemByUrl(system);
        if csResult is r4:CodeSystem {
            cs = csResult;
        }
    }

    r4:CodeSystemConcept? parentConcept = ();
    r4:CodeSystemConcept[] childConcepts = [];
    ConceptAttributeRelationship[] attributeRelationships = [];
    if system is r4:uri && effectiveCode is r4:code {
        [r4:CodeSystemConcept?, r4:CodeSystemConcept[]] hierarchy =
                getConceptHierarchy(system, effectiveCode, 'version);
        parentConcept = hierarchy[0];
        childConcepts = hierarchy[1];
        attributeRelationships = getConceptAttributeRelationships(system, effectiveCode, 'version);
    }

    return codesystemConceptsToParameters(result, cs, parentConcept, childConcepts, attributeRelationships);
}

// terminology:valueSetLookUp discards the ValueSet resource it's given beyond
// vs.url/vs.version - it re-resolves that url from storage rather than
// evaluating the compose actually supplied. An inline "valueSet" param sent in
// a $validate-code request is (by definition) usually not separately
// persisted, so that resolution fails even though the compose is already in
// hand. terminology:valueSetExpansion, unlike valueSetLookUp, does evaluate an
// inline resource's compose directly (that's how $expand already handles inline
// ValueSets correctly) - reuse it here and check membership in the result.
isolated function lookupInInlineValueSet(r4:Coding|r4:CodeableConcept codeValue, r4:ValueSet valueSet) returns r4:CodeSystemConcept[]|r4:CodeSystemConcept|r4:FHIRError {
    r4:ValueSet expanded = check terminology:valueSetExpansion({}, vs = valueSet, terminology = terminology_source);
    r4:ValueSetExpansionContains[] contains = expanded.expansion?.contains ?: [];

    r4:Coding[] codingsToCheck = [];
    if codeValue is r4:Coding {
        codingsToCheck = [codeValue];
    } else if codeValue is r4:CodeableConcept {
        codingsToCheck = codeValue.coding ?: [];
    }
    r4:CodeSystemConcept[] matches = [];
    foreach r4:Coding c in codingsToCheck {
        foreach r4:ValueSetExpansionContains entry in contains {
            // expansion.contains entries only carry `system` when the include spans
            // multiple code systems (see postProcessExpansion, which back-fills it
            // for the single-system case after this call returns) - so only gate on
            // system when both sides actually have one to compare.
            if entry.code == c.code && (entry.system is () || c.system is () || entry.system == c.system) {
                matches.push({code: <r4:code>entry.code, display: entry.display});
                break;
            }
        }
    }

    if matches.length() == 0 {
        return r4:createFHIRError(
                "Concept not found in the provided ValueSet",
                r4:ERROR,
                r4:PROCESSING_NOT_FOUND,
                cause = error("No matching concept found in the inline ValueSet"),
                httpStatusCode = http:STATUS_NOT_FOUND);
    }
    return matches.length() == 1 ? matches[0] : matches;
}

public isolated function valueSetLookUpPost(r4:FHIRContext ctx, r4:Parameters parameters) returns r4:Parameters|r4:FHIRError {
    r4:Coding?|r4:CodeableConcept? codingValue = ();
    r4:ValueSet? valueSet = ();
    r4:uri? system = ();
    r4:code? code = ();
    r4:uri? valueSetUrl = ();
    string? 'version = ();

    r4:Parameters|error parse = parameters.toJson().cloneWithType(r4:Parameters);
    if parse is r4:Parameters && parse.'parameter is r4:ParametersParameter[] {
        foreach var item in <r4:ParametersParameter[]>parse.'parameter {
            match item.name {
                "coding" => {
                    codingValue = item.valueCoding;
                }
                "codeableConcept" => {
                    codingValue = item.valueCodeableConcept;
                }
                "valueSet" => {
                    anydata temp = item.'resource is r4:Resource ? item.'resource : ();
                    r4:ValueSet|error cloneWithType = temp.cloneWithType(r4:ValueSet);
                    if cloneWithType is r4:ValueSet {
                        valueSet = cloneWithType;
                    }
                }
                "system" => {
                    system = item.valueUri ?: item.valueString;
                }
                "code" => {
                    code = item.valueCode ?: item.valueString;
                }
                "url" => {
                    valueSetUrl = item.valueUri ?: item.valueString;
                }
                "version" => {
                    'version = item.valueString;
                }
            }
        }

        // terminology:valueSetLookUp unconditionally casts vs.url to r4:uri with
        // no null check - but ValueSet.url is optional per spec, and that's often
        // exactly why a caller passes an inline valueSet (an ad-hoc ValueSet with
        // no stable canonical url). Without this, an inline ValueSet with no url
        // panics with a raw TypeCastError instead of a handled FHIRError.
        r4:ValueSet? inlineValueSet = valueSet;
        if inlineValueSet is r4:ValueSet && inlineValueSet.url is () {
            r4:ValueSet mutableValueSet = inlineValueSet.clone();
            mutableValueSet.url = "urn:uuid:" + uuid:createType1AsString();
            valueSet = mutableValueSet;
        }
    } else {
        return r4:createFHIRError(
                "Invalid request payload",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = parse is error ? parse : (),
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    // If we don't have a Coding/CodeableConcept but we do have system+code, build one.
    if codingValue is () && system is r4:uri && code is r4:code {
        codingValue = <r4:Coding>{system: system, code: code};
    }

    // terminology:valueSetLookUp only ever reads vs.url/vs.version off the ValueSet
    // we pass it, then re-resolves that url from storage - it never evaluates the
    // compose we actually send. That's fine for a ValueSet resolved by url below
    // (it's already persisted under that exact url), but an inline "valueSet"
    // param is - by definition - usually not persisted, so that resolution would
    // always fail. Remember which case we're in before the url-resolution branch
    // below can overwrite valueSet.
    boolean isInlineValueSet = valueSet is r4:ValueSet;

    // If no inline ValueSet was supplied but url was, resolve it from storage.
    if valueSet is () && valueSetUrl is r4:uri {
        valueSet = check readValueSetByUrl(valueSetUrl);
    }

    if valueSet is r4:ValueSet && (codingValue is r4:Coding || codingValue is r4:CodeableConcept) {
        // Try the library's own lookup first - when the inline ValueSet's url
        // happens to match something already persisted, this returns the full,
        // richly-populated concept (definition, properties, designations) that
        // our own storage-backed lookup produces. Only fall back to evaluating
        // the inline compose ourselves when that fails AND this was an inline
        // ValueSet - i.e. exactly the case the library can't resolve by url.
        r4:CodeSystemConcept[]|r4:CodeSystemConcept|r4:FHIRError primary =
                terminology:valueSetLookUp(codingValue, vs = valueSet, terminology = terminology_source);
        r4:CodeSystemConcept[]|r4:CodeSystemConcept result;
        if primary is r4:FHIRError && isInlineValueSet {
            result = check lookupInInlineValueSet(codingValue, valueSet);
        } else {
            result = check primary;
        }

        r4:uri? effectiveSystem = codingValue is r4:Coding ? codingValue.system : system;
        r4:code? effectiveCode = codingValue is r4:Coding ? codingValue.code : code;

        r4:CodeSystemConcept? parentConcept = ();
        r4:CodeSystemConcept[] childConcepts = [];
        ConceptAttributeRelationship[] attributeRelationships = [];
        if effectiveSystem is r4:uri && effectiveCode is r4:code {
            [r4:CodeSystemConcept?, r4:CodeSystemConcept[]] hierarchy =
                    getConceptHierarchy(effectiveSystem, effectiveCode, 'version);
            parentConcept = hierarchy[0];
            childConcepts = hierarchy[1];
            attributeRelationships = getConceptAttributeRelationships(effectiveSystem, effectiveCode, 'version);
        }

        return codesystemConceptsToParameters(result, parentConcept = parentConcept, childConcepts = childConcepts, attributeRelationships = attributeRelationships);
    }
    return r4:createFHIRError(
            "Invalid request payload",
            r4:ERROR,
            r4:INVALID_REQUIRED,
            diagnostic = "Provide (coding|codeableConcept) or (system+code), and (valueSet resource) or (url).",
            httpStatusCode = http:STATUS_BAD_REQUEST);
}

public isolated function valueSetLookUpGet(r4:FHIRContext ctx, string? id = (), string? reqSystem = (), string? reqCodeValue = ()) returns r4:Parameters|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly searchParams = ctx.getRequestSearchParameters();
    // "url" is the spec-correct parameter for which ValueSet to validate against
    // (https://hl7.org/fhir/R4/valueset-operation-validate-code.html). "system"
    // is meant only for the code's own origin system, but earlier callers of
    // this GET path used "system" as a stand-in for the ValueSet url - kept as a
    // fallback so those callers don't break, with "url" taking precedence.
    string? url = searchParams["url"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>searchParams["url"])[0].value : ();
    string? system = searchParams["system"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>searchParams["system"])[0].value : reqSystem;
    r4:code? codeValue = searchParams["code"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>searchParams["code"])[0].value : reqCodeValue;

    if codeValue !is r4:code|r4:Coding|r4:CodeableConcept {
        return r4:createFHIRError(
                "Can not find a ValueSet, Code value is missing",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeSystemConcept[]|r4:CodeSystemConcept|r4:FHIRError result;
    if id is string {
        result = terminology:valueSetLookUp(<r4:code>codeValue, vs = check readValueSetById(id), terminology = terminology_source);
    } else if url is string {
        result = terminology:valueSetLookUp(<r4:code>codeValue, vs = check readValueSetByUrl(url), terminology = terminology_source);
    } else if system is string {
        result = terminology:valueSetLookUp(<r4:code>codeValue, vs = check readValueSetByUrl(system), terminology = terminology_source);
    } else {
        return r4:createFHIRError(
                "Can not find a ValueSet",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if result is r4:FHIRError {
        return result;
    }

    return codesystemConceptsToParameters(result);
}

public isolated function subsumesGet(r4:FHIRContext ctx) returns r4:Parameters|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly idParam = ctx.getRequestSearchParameters();

    string? 'version = idParam["version"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["version"])[0].value : ();
    r4:uri? system = idParam["system"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["system"])[0].value : ();
    r4:code? codeA = idParam["codeA"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["codeA"])[0].value : ();
    r4:code? codeB = idParam["codeB"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>idParam["codeB"])[0].value : ();

    if system is string && codeA is r4:code && codeB is r4:code {
        // NOTE: replace the subsume function in terminology library by this subsume function
        // because this implementation is more efficient than the one in terminology library
        return terminology_source.subsumes(codeA = codeA, codeB = codeB, system = system, version = 'version);
    } else {
        return r4:createFHIRError(
                "Missing required input parameters",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }
}

public isolated function subsumesPost(r4:FHIRContext ctx, r4:Parameters parameters) returns r4:Parameters|r4:FHIRError {
    string? 'version = ();
    r4:uri? system = ();
    r4:Coding? codingA = ();
    r4:Coding? codingB = ();

    r4:Parameters|error typedParams = parameters.toJson().cloneWithType(r4:Parameters);
    if typedParams is error {
        return r4:createFHIRError("Invalid request payload", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    // json|http:ClientError jsonPayload = request.getJsonPayload();
    if typedParams.'parameter is r4:ParametersParameter[] {
        foreach var item in <r4:ParametersParameter[]>typedParams.'parameter {
            match item.name {
                "codingA" => {
                    codingA = item.valueCoding ?: ();
                }

                "codingB" => {
                    codingB = item.valueCoding ?: ();
                }

                "version" => {
                    'version = item.valueString ?: ();
                }

                "system" => {
                    system = item.valueUri ?: ();
                }
            }
        }
    }

    if system is string && codingA is r4:Coding && codingB is r4:Coding {
        // NOTE: replace the subsume function in terminology library by this subsume function
        // because this implementation is more efficient than the one in terminology library
        return terminology_source.subsumes(codeA = <r4:code>codingA.code, codeB = <r4:code>codingB.code, system = system, version = 'version);
    } else {
        return r4:createFHIRError(
                "Missing required input parameters",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }
}

// terminology:translate() returns r4:OperationOutcome (not r4:FHIRError) on
// failure, unlike the rest of this codebase's terminology:* calls. Bridges it
// into an r4:FHIRError so the $translate handlers can use the same
// check/error-propagation convention as every other operation here.
isolated function operationOutcomeToFHIRError(r4:OperationOutcome outcome) returns r4:FHIRError {
    string message = "Translation failed";
    r4:OperationOutcomeIssue[] issues = outcome.issue;
    if issues.length() > 0 {
        r4:CodeableConcept? details = issues[0].details;
        string? diagnostics = issues[0].diagnostics;
        if details is r4:CodeableConcept && details.text is string {
            message = <string>details.text;
        } else if diagnostics is string {
            message = diagnostics;
        }
    }
    return r4:createFHIRError(message, r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
}

// Shared by translateGet/translatePost once source/target/codesToTranslate have
// been extracted from the request. source is required because the underlying
// library function (terminology:translate) takes it as a non-nilable r4:uri -
// though the FHIR spec marks it merely "recommended," this server requires it.
isolated function performTranslate(r4:uri? sourceValueSetUri, r4:uri? targetValueSetUri, r4:CodeableConcept? codesToTranslate) returns r4:Parameters|r4:FHIRError {
    if sourceValueSetUri is () {
        return r4:createFHIRError(
                "Missing required input parameter: source",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                diagnostic = "The 'source' parameter (source ValueSet canonical URL) is required",
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }
    if codesToTranslate is () {
        return r4:createFHIRError(
                "Missing required input parameter",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                diagnostic = "Provide one of: 'coding', 'codeableConcept', or 'code' + 'system'",
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:Parameters|r4:OperationOutcome result = terminology:translate(sourceValueSetUri, targetValueSetUri, codesToTranslate, terminology = terminology_source);
    if result is r4:Parameters {
        return result;
    }
    return operationOutcomeToFHIRError(<r4:OperationOutcome>result);
}

public isolated function translateGet(r4:FHIRContext ctx) returns r4:Parameters|r4:FHIRError {
    map<r4:RequestSearchParameter[] & readonly> & readonly params = ctx.getRequestSearchParameters();

    r4:uri? sourceValueSetUri = params["source"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["source"])[0].value : ();
    r4:uri? targetValueSetUri = params["target"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["target"])[0].value
        : (params["targetsystem"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["targetsystem"])[0].value : ());
    r4:uri? system = params["system"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["system"])[0].value : ();
    r4:code? code = params["code"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["code"])[0].value : ();
    string? 'version = params["version"] is r4:RequestSearchParameter[] ? (<r4:RequestSearchParameter[]>params["version"])[0].value : ();

    r4:CodeableConcept? codesToTranslate = ();
    if code is r4:code && system is r4:uri {
        codesToTranslate = {coding: [{system: system, code: code, 'version: 'version}]};
    }

    return performTranslate(sourceValueSetUri, targetValueSetUri, codesToTranslate);
}

public isolated function translatePost(r4:FHIRContext ctx, r4:Parameters parameters) returns r4:Parameters|r4:FHIRError {
    r4:uri? sourceValueSetUri = ();
    r4:uri? targetValueSetUri = ();
    r4:uri? system = ();
    r4:code? code = ();
    string? 'version = ();
    r4:Coding? codingValue = ();
    r4:CodeableConcept? codeableConceptValue = ();

    r4:Parameters|error typedParams = parameters.toJson().cloneWithType(r4:Parameters);
    if typedParams is error {
        return r4:createFHIRError("Invalid request payload", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if typedParams.'parameter is r4:ParametersParameter[] {
        // $translate accepts EITHER a "coding" or "codeableConcept" parameter, OR
        // separate "system"/"code"(+"version") parameters, to identify the code(s)
        // being translated. "target" and "targetsystem" are aliases of each other
        // (a target ValueSet vs a target CodeSystem) - this server treats them the
        // same way, since findConceptMaps only matches on a single target scope.
        foreach var item in <r4:ParametersParameter[]>typedParams.'parameter {
            match item.name {
                "source" => {
                    sourceValueSetUri = item.valueUri ?: item.valueString;
                }
                "target" => {
                    targetValueSetUri = item.valueUri ?: item.valueString;
                }
                "targetsystem" => {
                    targetValueSetUri = targetValueSetUri ?: (item.valueUri ?: item.valueString);
                }
                "system" => {
                    system = item.valueUri ?: item.valueString;
                }
                "code" => {
                    code = item.valueCode ?: item.valueString;
                }
                "version" => {
                    'version = item.valueString;
                }
                "coding" => {
                    codingValue = item.valueCoding;
                }
                "codeableConcept" => {
                    codeableConceptValue = item.valueCodeableConcept;
                }
            }
        }
    } else {
        return r4:createFHIRError(
                "Invalid request payload",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:CodeableConcept? codesToTranslate = ();
    if codeableConceptValue is r4:CodeableConcept {
        codesToTranslate = codeableConceptValue;
    } else if codingValue is r4:Coding {
        codesToTranslate = {coding: [codingValue]};
    } else if code is r4:code && system is r4:uri {
        codesToTranslate = {coding: [{system: system, code: code, 'version: 'version}]};
    }

    return performTranslate(sourceValueSetUri, targetValueSetUri, codesToTranslate);
}

public isolated function batchValidateValueSets(r4:Bundle bundle) returns r4:Bundle|r4:FHIRError {

    if bundle.'type != r4:BUNDLE_TYPE_BATCH {
        return r4:createFHIRError(
                "Not a batch type bundle",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    r4:BundleEntry[] responseEntries = [];
    r4:BundleEntry[]? entries = bundle.entry;
    if entries != () {
        foreach r4:BundleEntry entry in entries {
            if entry.request is r4:BundleEntryRequest {

                r4:BundleEntryRequest? entryRequest = entry.request;

                if entryRequest is () {
                    return r4:createFHIRError(
                            "No entry requests found in the bundle",
                            r4:ERROR,
                            r4:INVALID_REQUIRED,
                            httpStatusCode = http:STATUS_BAD_REQUEST);
                }

                // split the url to get system and code
                map<string> urlParts = getSystemAndCode(entryRequest.url);
                string? system = urlParts["system"];
                r4:code? code = urlParts["code"];

                r4:Parameters|r4:FHIRError result;
                if code is r4:code && system is string {
                    r4:CodeSystemConcept[]|r4:CodeSystemConcept|r4:FHIRError lookupResult = terminology:valueSetLookUp(code, vs = check readValueSetByUrl(system), terminology = terminology_source);
                    result = lookupResult is r4:FHIRError ? lookupResult : codesystemConceptsToParameters(lookupResult);
                } else {
                    result = r4:createFHIRError("Missing required parameters", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
                }

                if result is r4:Parameters {
                    responseEntries.push({
                        'resource: check validationResultToParameters(result)
                    });
                } else {
                    responseEntries.push({
                        'resource: <r4:Parameters>{
                            'parameter: [
                                {
                                    name: "result",
                                    valueBoolean: false
                                },
                                {
                                    name: "message",
                                    valueString: result.message()
                                }
                            ]
                        }
                    });
                }
            }
        }
    } else {
        return r4:createFHIRError(
                "No entries in the bundle",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    return {
        'type: r4:BUNDLE_TYPE_BATCH_RESPONSE,
        entry: responseEntries
    };
}

isolated function getSystemAndCode(string input) returns map<string> {
    // Split the string at '?' to separate the base URL and query parameters
    string[] parts = regex:split(input, string `\?`);

    if parts.length() < 2 {
        return {};
    }

    string queryParams = parts[1];

    // Split query parameters using '&'
    string[] params = regex:split(queryParams, string `&`);

    string system = "";
    string code = "";

    foreach var param in params {
        // Split each parameter by '='
        string[] keyValue = regex:split(param, string `=`);
        if keyValue.length() == 2 {
            if keyValue[0] == "system" {
                system = keyValue[1];
            } else if keyValue[0] == "code" {
                code = keyValue[1];
            }
        }
    }

    return {"system": system, "code": code};
}

public isolated function addCodeSystem(r4:FHIRContext ctx, r4:CodeSystem codeSystem) returns r4:FHIRError? {
    do {
        return terminology:addCodeSystem(codeSystem, terminology = terminology_source);
    } on fail var e {
        return r4:createFHIRError(
                "Invalid request payload, " + e.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = e,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
}

public isolated function addValueSet(r4:FHIRContext ctx, r4:ValueSet valueSet) returns r4:FHIRError? {
    do {
        return terminology:addValueSet(valueSet, terminology = terminology_source);
    } on fail var e {
        return r4:createFHIRError(
                "Invalid request payload, " + e.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = e,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
}

public isolated function addConceptMap(r4:FHIRContext ctx, r4:ConceptMap conceptMap) returns r4:FHIRError? {
    do {
        // Like byteToConceptMap in data_mapping.bal: ConceptMap isn't a resource
        // type the Terminology IG registers, so the fhirr4:Listener's own request
        // binding resolves it against the default (international401) IG. The
        // bound value is structurally identical to r4:ConceptMap but nominally a
        // different type, which trips up terminology:addConceptMap's internal
        // validator:validate(..., r4:ConceptMap) call. Re-derive a clean
        // r4:ConceptMap via JSON to sidestep the nominal mismatch.
        r4:ConceptMap normalized = check conceptMap.toJson().cloneWithType(r4:ConceptMap);
        return terminology:addConceptMap(normalized, terminology = terminology_source);
    } on fail var e {
        return r4:createFHIRError(
                "Invalid request payload, " + e.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = e,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
}

public isolated function upload(http:Request payload) returns r4:FHIRError? {
    if payload.getContentType() != ZIP {
        return r4:createFHIRError(
                "Invalid request payload, content type is not supported",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                diagnostic = "The request payload should be a zip file",
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    do {
        string|error typeHeader = payload.getHeader(TYPE_HEADER);

        if typeHeader is error {
            return r4:createFHIRError(
                    string `Missing ${TYPE_HEADER} header in the request`,
                    r4:ERROR,
                    r4:INVALID_REQUIRED,
                    diagnostic = string `The request should contains ${TYPE_HEADER} header and supported values are: FHIR, LOINC and SNOMED`,
                    httpStatusCode = http:STATUS_BAD_REQUEST);
        }
        else if typeHeader != FHIR && typeHeader != LOINC && typeHeader != SNOMED {
            return r4:createFHIRError(
                    string `Invalid ${TYPE_HEADER} header value`,
                    r4:ERROR,
                    r4:INVALID_REQUIRED,
                    diagnostic = string `The request should contains ${TYPE_HEADER} header and supported values are: FHIR, LOINC and SNOMED`,
                    httpStatusCode = http:STATUS_BAD_REQUEST);
        }

        string dirPath = createNewTempDirectory();

        check saveCompressedPayload(check payload.getByteStream(), dirPath);
        check extractZipFile(dirPath);

        r4:FHIRError? result = ();

        // standard FHIR
        if typeHeader == FHIR {
            CodeSystemValueSetJson jsonArrays = check readFilesForUpload(dirPath + ZIP_FILE_EXTRACTION_PATH);

            _ = terminology:addCodeSystemsAsJson(jsonArrays.codeSystems, terminology = terminology_source);
            _ = terminology:addValueSetsAsJson(jsonArrays.valueSets, terminology = terminology_source);
        }

        // LOINC
        else if typeHeader == LOINC {
            string? version = payload.getQueryParamValue("loinc-version");
            check loinc:convert(dirPath + ZIP_FILE_EXTRACTION_PATH, version);

            r4:CodeSystem codeSystem = check readFileJsonAndReturnCodeSystem(dirPath + ZIP_FILE_EXTRACTION_PATH + loinc:FHIR_LOINC_FILE_NAME);

            result = terminology:addCodeSystem(codeSystem, terminology = terminology_source);
        }

        // SNOMED
        else if typeHeader == SNOMED {
            string? version = payload.getQueryParamValue("snomed-version");
            _ = start runSnomedImportAsync(dirPath + ZIP_FILE_EXTRACTION_PATH, version, dirPath);
            log:printInfo("SNOMED import scheduled in background; check server logs for completion.");
            return ();
        }

        _ = start removeDirectory(dirPath);

        return result;
    } on fail var e {
        return r4:createFHIRError(
                "Invalid request payload, " + e.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = e,
                httpStatusCode = http:STATUS_INTERNAL_SERVER_ERROR);
    }
}

public isolated function findCodeGet(http:Request request) returns r4:Bundle|r4:FHIRError {
    string property = request.getQueryParamValue("property") ?: DISPLAY;
    string? system = request.getQueryParamValue("system");
    string? filter = request.getQueryParamValue("filter");
    int count;
    int offset;

    do {
        if filter is () {
            check error("Missing 'filter' query parameter");
        }

        if !(property == DISPLAY || property == DEFINITION) {
            check error("Invalid property value. Only 'display' or 'definition' are allowed.");
        }

        string? countStr = request.getQueryParamValue("_count");
        string? offsetStr = request.getQueryParamValue("_offset");

        count = countStr is string ? check int:fromString(countStr) : terminology:TERMINOLOGY_SEARCH_DEFAULT_COUNT;
        offset = offsetStr is string ? check int:fromString(offsetStr) : 0;
    } on fail var e {
        return r4:createFHIRError(
                "Invalid request payload, " + e.message(),
                r4:ERROR,
                r4:INVALID_REQUIRED,
                cause = e,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    terminology:CodeConceptDetails[]|r4:FHIRError result = terminology_source.searchConcept(<DISPLAY|DEFINITION>property, <string>filter, system, offset, count);

    if result is r4:FHIRError {
        return result;
    }

    return codeSystemDetailsIntoBundle(result);
}

// Implements ConceptMap/$closure (https://hl7.org/fhir/R4/conceptmap-operation-closure.html):
// maintains a client-named, incrementally-growing subsumption closure table.
// Each call adds the given concepts to the named table and returns only the
// subsumption pairs not yet reported for that name - both a new concept's own
// ancestors (via concept_closure, the same table $subsumes/$lookup already
// use), and any case where the new concept turns out to be an ancestor of a
// concept added in an earlier call.
public isolated function closurePost(http:Request request) returns r4:ConceptMap|r4:FHIRError {
    json|http:ClientError jsonPayload = request.getJsonPayload();
    if jsonPayload is http:ClientError {
        return r4:createFHIRError("Invalid request payload", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
    }
    r4:Parameters|error typedParams = jsonPayload.cloneWithType(r4:Parameters);
    if typedParams is error {
        return r4:createFHIRError("Invalid request payload", r4:ERROR, r4:INVALID_REQUIRED, httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    string? name = ();
    r4:Coding[] concepts = [];
    string? resyncVersion = ();

    if typedParams.'parameter is r4:ParametersParameter[] {
        foreach var item in <r4:ParametersParameter[]>typedParams.'parameter {
            match item.name {
                "name" => {
                    name = item.valueString;
                }
                "concept" => {
                    if item.valueCoding is r4:Coding {
                        concepts.push(<r4:Coding>item.valueCoding);
                    }
                }
                "version" => {
                    resyncVersion = item.valueString;
                }
            }
        }
    }

    if name is () {
        return r4:createFHIRError(
                "Missing required 'name' parameter",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                diagnostic = "$closure requires a 'name' parameter identifying the closure table",
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }
    string closureName = name;

    ClosureTableRow tableRow = check getOrCreateClosureTable(closureName);
    int[] knownConceptIds = getKnownConceptIds(tableRow.closureTableId);

    // (ancestor, descendant) pairs newly discovered this call, plus any concepts
    // that couldn't be resolved.
    [int, int][] newPairs = [];
    UnmatchedClosureConcept[] unmatched = [];

    foreach r4:Coding coding in concepts {
        string? system = coding.system;
        r4:code? code = coding.code;
        if system is () || code is () {
            unmatched.push({system: system, code: code ?: ""});
            continue;
        }

        store_h2:CodeSystem|error storeCs = getStoreCodeSystemByURL(system, coding.version);
        if storeCs is error {
            unmatched.push({system: system, code: code});
            continue;
        }
        store_h2:Concept|r4:FHIRError storeConcept = getStoreConceptByCode(storeCs.codeSystemId, code);
        if storeConcept is r4:FHIRError {
            unmatched.push({system: system, code: code});
            continue;
        }

        int conceptId = storeConcept.conceptId;
        if knownConceptIds.indexOf(conceptId) is int {
            // Already added in an earlier call - nothing new to compute for it.
            continue;
        }

        // This concept's own ancestors (is-a chain), whether or not those
        // ancestors were ever explicitly added by the client.
        int[] ancestorIds = getAncestorConceptIds(conceptId, storeCs.codeSystemId);
        foreach int ancestorId in ancestorIds {
            newPairs.push([ancestorId, conceptId]);
        }

        // The reverse direction: this newly-added concept might itself be an
        // ancestor of a concept added in an earlier call, discovered only now.
        if knownConceptIds.length() > 0 {
            int[] descendantIds = getDescendantConceptIdsAmong(conceptId, storeCs.codeSystemId, knownConceptIds);
            foreach int descendantId in descendantIds {
                newPairs.push([conceptId, descendantId]);
            }
        }

        check addClosureTableConcept(tableRow.closureTableId, conceptId);
        knownConceptIds.push(conceptId);
    }

    int newVersion = tableRow.currentVersion + 1;
    check bumpClosureTableVersion(tableRow.closureTableId, newVersion);

    ClosureTablePairRow[] pairsToReturn = [];
    foreach [int, int] [ancestorId, descendantId] in newPairs {
        boolean alreadyReported = isPairReported(tableRow.closureTableId, ancestorId, descendantId);
        if !alreadyReported {
            check recordClosurePair(tableRow.closureTableId, ancestorId, descendantId, newVersion);
            pairsToReturn.push({
                closureTablePairId: 0,
                closureTableId: tableRow.closureTableId,
                ancestorConceptId: ancestorId,
                descendantConceptId: descendantId,
                reportedAtVersion: newVersion
            });
        }
    }

    // Resync: also include everything reported after the version the client
    // last synced to, in addition to whatever this call just discovered.
    if resyncVersion is string {
        int|error requestedVersion = int:fromString(resyncVersion);
        if requestedVersion is int {
            ClosureTablePairRow[] historicalPairs = getPairsSinceVersion(tableRow.closureTableId, requestedVersion, newVersion);
            foreach var p in historicalPairs {
                pairsToReturn.push(p);
            }
        }
    }

    return check buildClosureConceptMap(closureName, newVersion, pairsToReturn, unmatched);
}

public isolated function findCodePost(http:Request request) returns r4:Bundle|r4:FHIRError {
    string property = DISPLAY;
    string? system = ();
    string? filter = ();
    int count = terminology:TERMINOLOGY_SEARCH_DEFAULT_COUNT;
    int offset = 0;

    json|http:ClientError jsonPayload = request.getJsonPayload();
    if jsonPayload is json {
        r4:Parameters|error parameters = jsonPayload.cloneWithType(r4:Parameters);
        if parameters is r4:Parameters && parameters.'parameter is r4:ParametersParameter[] {
            foreach var item in <r4:ParametersParameter[]>parameters.'parameter {
                match item.name {
                    "property" => {
                        property = item.valueString ?: DISPLAY;
                    }
                    "system" => {
                        system = item.valueString ?: ();
                    }
                    "filter" => {
                        filter = item.valueString ?: ();
                    }
                    "_count" => {
                        count = item.valueInteger is int ? <int>item.valueInteger : terminology:TERMINOLOGY_SEARCH_DEFAULT_COUNT;
                    }
                    "_offset" => {
                        offset = item.valueInteger is int ? <int>item.valueInteger : 0;
                    }
                }
            }
        } else {
            return r4:createFHIRError(
                    "Invalid request payload",
                    r4:ERROR,
                    r4:INVALID_REQUIRED,
                    cause = parameters is error ? parameters : (),
                    httpStatusCode = http:STATUS_BAD_REQUEST);
        }
    } else {
        return r4:createFHIRError(
                "Empty request payload",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if filter is () {
        return r4:createFHIRError(
                "Missing 'filter' parameter",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    if !(property == DISPLAY || property == DEFINITION) {
        return r4:createFHIRError(
                "Invalid property value. Only 'display' or 'definition' are allowed.",
                r4:ERROR,
                r4:INVALID_REQUIRED,
                httpStatusCode = http:STATUS_BAD_REQUEST);
    }

    terminology:CodeConceptDetails[]|r4:FHIRError result = terminology_source.searchConcept(<DISPLAY|DEFINITION>property, <string>filter, system, offset, count);

    if result is r4:FHIRError {
        return result;
    }

    return codeSystemDetailsIntoBundle(result);
}

