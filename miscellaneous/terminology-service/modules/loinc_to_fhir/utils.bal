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
import ballerinax/health.fhir.r4;

public const string FHIR_LOINC_FILE_NAME = "/loinc-codesystem.json";
const string LOINC_CSV_FILE_PATH = "/LoincTable/Loinc.csv";

// Mapping function
isolated function LoincConceptToR4Concept(LoincConcept[]? loincConcepts) returns r4:CodeSystemConcept[] {
    if loincConcepts is null {
        return [];
    }

    r4:CodeSystemConcept[] r4Concepts = [];
    foreach LoincConcept loinc in loincConcepts {
        // LONG_COMMON_NAME is the human-readable clinical display (e.g. "Hospice care
        // Note"); COMPONENT is just one axis of the 6-part LOINC name (e.g. "Note") and
        // is meaningless as a display on its own. Fall back to COMPONENT only when
        // LONG_COMMON_NAME is absent.
        string? longCommonName = loinc?.LONG_COMMON_NAME;
        string display = longCommonName is string && longCommonName != "" ? longCommonName : loinc.COMPONENT;

        r4:CodeSystemConcept concept = {
            code: loinc.LOINC_NUM,
            display: display,
            designation: getDesignations(loinc),
            property: getProperties(loinc)
        };
        r4Concepts.push(concept);
    }
    return r4Concepts;
}

// Builds designations from LOINC's display-name variants. Each is tagged with
// its LOINC field name as the designation's use.code so a $lookup consumer can
// tell which variant (long common name, short name, consumer-friendly name) a
// given entry is.
isolated function getDesignations(LoincConcept loinc) returns r4:CodeSystemConceptDesignation[] {
    r4:CodeSystemConceptDesignation[] designations = [];

    string? longCommonName = loinc?.LONG_COMMON_NAME;
    if longCommonName is string && longCommonName != "" {
        designations.push({
            language: "en-US",
            value: longCommonName,
            use: {system: "http://loinc.org", code: "LONG_COMMON_NAME"}
        });
    }

    string? shortName = loinc?.SHORTNAME;
    if shortName is string && shortName != "" {
        designations.push({
            language: "en-US",
            value: shortName,
            use: {system: "http://loinc.org", code: "SHORTNAME"}
        });
    }

    string? consumerName = loinc?.CONSUMER_NAME;
    if consumerName is string && consumerName != "" {
        designations.push({
            language: "en-US",
            value: consumerName,
            use: {system: "http://loinc.org", code: "CONSUMER_NAME"}
        });
    }

    return designations;
}

// Function to extract all properties dynamically from a LoincConcept
isolated function getProperties(LoincConcept loinc) returns r4:CodeSystemConceptProperty[] {
    r4:CodeSystemConceptProperty[] properties = [];

    // Manually map each field in the LoincConcept record
    if loinc?.PROPERTY is string && loinc?.PROPERTY != "" {
        properties.push({code: "PROPERTY", valueString: loinc?.PROPERTY});
    }
    if loinc?.TIME_ASPCT is string && loinc?.TIME_ASPCT != "" {
        properties.push({code: "TIME_ASPCT", valueString: loinc?.TIME_ASPCT});
    }
    if loinc?.SYSTEM is string && loinc?.SYSTEM != "" {
        properties.push({code: "SYSTEM", valueString: loinc?.SYSTEM});
    }
    if loinc?.SCALE_TYP is string && loinc?.SCALE_TYP != "" {
        properties.push({code: "SCALE_TYP", valueString: loinc?.SCALE_TYP});
    }
    if loinc?.METHOD_TYP is string && loinc?.METHOD_TYP != "" {
        properties.push({code: "METHOD_TYP", valueString: loinc?.METHOD_TYP});
    }
    if loinc?.CLASS is string && loinc?.CLASS != "" {
        properties.push({code: "CLASS", valueString: loinc?.CLASS});
    }
    // STATUS mapped to the shared "status" property code (lowercased LOINC value:
    // active/trial/discouraged/deprecated) so codesystemConceptsToParameters' existing
    // inactive-derivation (status == retired/deprecated) picks up deprecated LOINC
    // codes the same way it already does for SNOMED. discouraged/trial are not
    // inactive - those codes are still valid for use, just not preferred.
    string? status = loinc?.STATUS;
    if status is string && status != "" {
        properties.push({code: "status", valueCode: status.toLowerAscii()});
    }
    if loinc?.CLASSTYPE is string && loinc?.CLASSTYPE != "" {
        properties.push({code: "CLASSTYPE", valueString: loinc?.CLASSTYPE});
    }
    if loinc?.FORMULA is string && loinc?.FORMULA != "" {
        properties.push({code: "FORMULA", valueString: loinc?.FORMULA});
    }
    if loinc?.EXMPL_ANSWERS is string && loinc?.EXMPL_ANSWERS != "" {
        properties.push({code: "EXMPL_ANSWERS", valueString: loinc?.EXMPL_ANSWERS});
    }
    if loinc?.SURVEY_QUEST_TEXT is string && loinc?.SURVEY_QUEST_TEXT != "" {
        properties.push({code: "SURVEY_QUEST_TEXT", valueString: loinc?.SURVEY_QUEST_TEXT});
    }
    if loinc?.SURVEY_QUEST_SRC is string && loinc?.SURVEY_QUEST_SRC != "" {
        properties.push({code: "SURVEY_QUEST_SRC", valueString: loinc?.SURVEY_QUEST_SRC});
    }
    if loinc?.UNITSREQUIRED is string && loinc?.UNITSREQUIRED != "" {
        properties.push({code: "UNITSREQUIRED", valueString: loinc?.UNITSREQUIRED});
    }
    if loinc?.RELATEDNAMES2 is string && loinc?.RELATEDNAMES2 != "" {
        properties.push({code: "RELATEDNAMES2", valueString: loinc?.RELATEDNAMES2});
    }
    if loinc?.ORDER_OBS is string && loinc?.ORDER_OBS != "" {
        properties.push({code: "ORDER_OBS", valueString: loinc?.ORDER_OBS});
    }
    if loinc?.HL7_FIELD_SUBFIELD_ID is string && loinc?.HL7_FIELD_SUBFIELD_ID != "" {
        properties.push({code: "HL7_FIELD_SUBFIELD_ID", valueString: loinc?.HL7_FIELD_SUBFIELD_ID});
    }
    if loinc?.EXTERNAL_COPYRIGHT_NOTICE is string && loinc?.EXTERNAL_COPYRIGHT_NOTICE != "" {
        properties.push({code: "EXTERNAL_COPYRIGHT_NOTICE", valueString: loinc?.EXTERNAL_COPYRIGHT_NOTICE});
    }
    if loinc?.EXAMPLE_UNITS is string && loinc?.EXAMPLE_UNITS != "" {
        properties.push({code: "EXAMPLE_UNITS", valueString: loinc?.EXAMPLE_UNITS});
    }
    if loinc?.EXAMPLE_UCUM_UNITS is string && loinc?.EXAMPLE_UCUM_UNITS != "" {
        properties.push({code: "EXAMPLE_UCUM_UNITS", valueString: loinc?.EXAMPLE_UCUM_UNITS});
    }
    if loinc?.STATUS_REASON is string && loinc?.STATUS_REASON != "" {
        properties.push({code: "STATUS_REASON", valueString: loinc?.STATUS_REASON});
    }
    if loinc?.STATUS_TEXT is string && loinc?.STATUS_TEXT != "" {
        properties.push({code: "STATUS_TEXT", valueString: loinc?.STATUS_TEXT});
    }
    if loinc?.CHANGE_REASON_PUBLIC is string && loinc?.CHANGE_REASON_PUBLIC != "" {
        properties.push({code: "CHANGE_REASON_PUBLIC", valueString: loinc?.CHANGE_REASON_PUBLIC});
    }
    if loinc?.HL7_ATTACHMENT_STRUCTURE is string && loinc?.HL7_ATTACHMENT_STRUCTURE != "" {
        properties.push({code: "HL7_ATTACHMENT_STRUCTURE", valueString: loinc?.HL7_ATTACHMENT_STRUCTURE});
    }
    if loinc?.PanelType is string && loinc?.PanelType != "" {
        properties.push({code: "PanelType", valueString: loinc?.PanelType});
    }
    if loinc?.AskAtOrderEntry is string && loinc?.AskAtOrderEntry != "" {
        properties.push({code: "AskAtOrderEntry", valueString: loinc?.AskAtOrderEntry});
    }
    if loinc?.AssociatedObservations is string && loinc?.AssociatedObservations != "" {
        properties.push({code: "AssociatedObservations", valueString: loinc?.AssociatedObservations});
    }
    if loinc?.ValidHL7AttachmentRequest is string && loinc?.ValidHL7AttachmentRequest != "" {
        properties.push({code: "ValidHL7AttachmentRequest", valueString: loinc?.ValidHL7AttachmentRequest});
    }

    return properties;
}

isolated function createCodeSystemResource(LoincConcept[]? concepts, string? 'version) returns r4:CodeSystem|error {
    r4:CodeSystem codeSystem = {
        resourceType: "CodeSystem",
        id: "loinc",
        url: "http://loinc.org",
        name: "LOINC",
        title: "Logical Observation Identifiers Names and Codes",
        status: r4:CODE_STATUS_ACTIVE,
        content: r4:CODE_CONTENT_COMPLETE,
        caseSensitive: true,
        hierarchyMeaning: r4:CODE_HIERARCHYMEANING_IS_A
    };

    codeSystem.concept = LoincConceptToR4Concept(concepts);

    if ('version is string) {
        codeSystem.version = 'version;
    }

    return codeSystem;
}
