#import ballerina/time;

public const string SNOMED_SYSTEM_URL = "http://snomed.info/sct";
public const string SNOMED_CODE_SYSTEM_ID = "snomed-ct";
public const string SNOMED_CODE_SYSTEM_NAME = "SNOMEDCT";
public const string SNOMED_CODE_SYSTEM_TITLE = "SNOMED CT";
public const string SNOMED_PUBLISHER = "SNOMED International";

public const string SNOMED_FSN_TYPE_ID = "900000000000003001";
public const string SNOMED_SYNONYM_TYPE_ID = "900000000000013009";

public type SnomedConceptRow record {|
    string id;
    string effectiveTime;
    string active;
    string moduleId;
    string definitionStatusId;
|};

public type SnomedDescriptionRow record {|
    string id;
    string effectiveTime;
    string active;
    string moduleId;
    string conceptId;
    string languageCode;
    string typeId;
    string term;
    string caseSignificanceId;
|};

public type SnomedTextDefinitionRow record {|
    string id;
    string effectiveTime;
    string active;
    string moduleId;
    string conceptId;
    string languageCode;
    string typeId;
    string term;
    string caseSignificanceId;
|};

public type SnomedConceptImport record {|
    string code;
    string display;
    string? definition;
    string effectiveTime;
    string active;
    string moduleId;
    string definitionStatusId;
    string? fsn;
    string[] synonyms;
    string? caseSignificanceId;
|};

public type SnomedImportSummary record {|
    string codeSystemId;
    string system;
    string version;
    int conceptsRead;
    int conceptsImported;
    int descriptionsRead;
    int textDefinitionsRead;
|};