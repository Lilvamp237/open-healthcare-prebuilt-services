-- AUTO-GENERATED FILE.

-- This file is an auto-generated file by Ballerina persistence layer for model.
-- Please verify the generated scripts and execute them against the target DB server.

DROP TABLE IF EXISTS "concept_relationships";
DROP TABLE IF EXISTS "concept_closure";
DROP TABLE IF EXISTS "valueset_compose_include_value_sets";
DROP TABLE IF EXISTS "valueset_compose_include_concepts";
DROP TABLE IF EXISTS "valueset_compose_includes";
DROP TABLE IF EXISTS "concepts";
DROP TABLE IF EXISTS "valuesets";
DROP TABLE IF EXISTS "codesystems";

CREATE TABLE "codesystems" (
	"codeSystemId"  SERIAL,
	"id" VARCHAR(191) NOT NULL,
	"url" VARCHAR(191) NOT NULL,
	"version" VARCHAR(191) NOT NULL,
	"name" VARCHAR(191) NOT NULL,
	"title" VARCHAR(191) NOT NULL,
	"status" VARCHAR(191) NOT NULL,
	"date" VARCHAR(191) NOT NULL,
	"publisher" VARCHAR(191) NOT NULL,
	"codeSystem" BYTEA NOT NULL,
	PRIMARY KEY("codeSystemId")
);

CREATE TABLE "valuesets" (
	"valueSetId"  SERIAL,
	"id" VARCHAR(191) NOT NULL,
	"url" VARCHAR(191) NOT NULL,
	"version" VARCHAR(191) NOT NULL,
	"name" VARCHAR(191) NOT NULL,
	"title" VARCHAR(191) NOT NULL,
	"status" VARCHAR(191) NOT NULL,
	"date" VARCHAR(191) NOT NULL,
	"publisher" VARCHAR(191) NOT NULL,
	"valueSet" BYTEA NOT NULL,
	PRIMARY KEY("valueSetId")
);

CREATE TABLE "valueset_compose_includes" (
	"valueSetComposeIncludeId"  SERIAL,
	"systemFlag" BOOLEAN NOT NULL,
	"valueSetFlag" BOOLEAN NOT NULL,
	"conceptFlag" BOOLEAN NOT NULL,
	"codeSystemId" INT,
	"valuesetValueSetId" INT NOT NULL,
	FOREIGN KEY("valuesetValueSetId") REFERENCES "valuesets"("valueSetId"),
	PRIMARY KEY("valueSetComposeIncludeId")
);

CREATE TABLE "concepts" (
	"conceptId"  SERIAL,
	"code" VARCHAR(191) NOT NULL,
	"display" VARCHAR(191),
	"definition" VARCHAR(191),
	"concept" BYTEA NOT NULL,
	"parentConceptId" INT,
	"codesystemCodeSystemId" INT NOT NULL,
	FOREIGN KEY("codesystemCodeSystemId") REFERENCES "codesystems"("codeSystemId"),
	PRIMARY KEY("conceptId")
);

CREATE TABLE "valueset_compose_include_concepts" (
	"valueSetComposeIncludeConceptId"  SERIAL,
	"valuesetcomposeValueSetComposeIncludeId" INT NOT NULL,
	FOREIGN KEY("valuesetcomposeValueSetComposeIncludeId") REFERENCES "valueset_compose_includes"("valueSetComposeIncludeId"),
	"conceptConceptId" INT NOT NULL,
	FOREIGN KEY("conceptConceptId") REFERENCES "concepts"("conceptId"),
	PRIMARY KEY("valueSetComposeIncludeConceptId")
);

CREATE TABLE "valueset_compose_include_value_sets" (
	"valueSetComposeIncludeValueSetId"  SERIAL,
	"valuesetcomposeValueSetComposeIncludeId" INT NOT NULL,
	FOREIGN KEY("valuesetcomposeValueSetComposeIncludeId") REFERENCES "valueset_compose_includes"("valueSetComposeIncludeId"),
	"valuesetValueSetId" INT NOT NULL,
	FOREIGN KEY("valuesetValueSetId") REFERENCES "valuesets"("valueSetId"),
	PRIMARY KEY("valueSetComposeIncludeValueSetId")
);

-- SNOMED CT transitive is-a closure.
CREATE TABLE "concept_closure" (
	"closureId"  SERIAL,
	"ancestorConceptId" INT NOT NULL,
	"descendantConceptId" INT NOT NULL,
	"depth" INT NOT NULL,
	"codeSystemId" INT NOT NULL,
	PRIMARY KEY("closureId")
);

-- SNOMED CT non-is-a clinical attribute relationships (Finding site, Associated
-- morphology, etc), from Relationship rows where typeId != 116680003.
CREATE TABLE "concept_relationships" (
	"relationshipId"  SERIAL,
	"sourceConceptId" INT NOT NULL,
	"typeId" VARCHAR(191) NOT NULL,
	"destinationConceptId" INT NOT NULL,
	"codeSystemId" INT NOT NULL,
	PRIMARY KEY("relationshipId")
);

-- CodeSystem/$lookup, CodeSystem/$subsumes, CodeSystem read-by-id, CodeSystem search
CREATE INDEX "idx_codesystems_id" ON "codesystems"("id");
CREATE INDEX "idx_codesystems_url" ON "codesystems"("url");
CREATE INDEX "idx_codesystems_url_version" ON "codesystems"("url", "version");
CREATE INDEX "idx_codesystems_status" ON "codesystems"("status");
CREATE INDEX "idx_codesystems_name" ON "codesystems"("name");

-- ValueSet/$expand, ValueSet/$validate-code, ValueSet read-by-id, ValueSet search
CREATE INDEX "idx_valuesets_id" ON "valuesets"("id");
CREATE INDEX "idx_valuesets_url" ON "valuesets"("url");
CREATE INDEX "idx_valuesets_url_version" ON "valuesets"("url", "version");
CREATE INDEX "idx_valuesets_status" ON "valuesets"("status");
CREATE INDEX "idx_valuesets_name" ON "valuesets"("name");

-- $lookup, $validate-code, $find-code, $subsumes hierarchy traversal
CREATE INDEX "idx_concepts_codesystem_id" ON "concepts"("codesystemCodeSystemId");
CREATE INDEX "idx_concepts_code" ON "concepts"("code");
CREATE INDEX "idx_concepts_codesystem_code" ON "concepts"("codesystemCodeSystemId", "code");
CREATE INDEX "idx_concepts_parent" ON "concepts"("parentConceptId");
CREATE INDEX "idx_concepts_display" ON "concepts"("display");

-- ValueSet/$expand: compose include traversal
CREATE INDEX "idx_vci_valueset_id" ON "valueset_compose_includes"("valuesetValueSetId");
CREATE INDEX "idx_vci_codesystem_id" ON "valueset_compose_includes"("codeSystemId");

-- Join tables for $expand
CREATE INDEX "idx_vcic_compose_id" ON "valueset_compose_include_concepts"("valuesetcomposeValueSetComposeIncludeId");
CREATE INDEX "idx_vcic_concept_id" ON "valueset_compose_include_concepts"("conceptConceptId");
CREATE INDEX "idx_vcivs_compose_id" ON "valueset_compose_include_value_sets"("valuesetcomposeValueSetComposeIncludeId");
CREATE INDEX "idx_vcivs_valueset_id" ON "valueset_compose_include_value_sets"("valuesetValueSetId");

-- CodeSystem/$subsumes and hierarchy-based ValueSet/$expand over the SNOMED closure
CREATE INDEX "idx_closure_ancestor" ON "concept_closure"("codeSystemId", "ancestorConceptId");
CREATE INDEX "idx_closure_descendant" ON "concept_closure"("codeSystemId", "descendantConceptId");
CREATE INDEX "idx_closure_pair" ON "concept_closure"("ancestorConceptId", "descendantConceptId");

CREATE INDEX "idx_relationships_source" ON "concept_relationships"("codeSystemId", "sourceConceptId");
