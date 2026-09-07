# Running the HL7 Terminology Ecosystem Conformance Suite

## 1. Get the validator

Download `validator_cli.jar` from either:

- https://hl7.org/fhir/R4/validation.html
- https://github.com/hapifhir/org.hl7.fhir.core/releases

## 2. Start the server

Postgres must be up with SNOMED/LOINC loaded, or point the service at your own DB.

```sh
cd miscellaneous/terminology-service
bal run
```

The service listens on `http://localhost:9090`.

## 3. Load the `simple-cases` suite's setup files

`POST /CodeSystem` and `POST /ValueSet` reject a resource whose `url`+`version`
already exists (`400`), so only run this once per DB.

```powershell
$T = "$env:USERPROFILE\.fhir\packages\hl7.fhir.uv.tx-ecosystem#current\package\tests"

curl.exe -X POST "http://localhost:9090/fhir/r4/CodeSystem" -H "Content-Type: application/fhir+json" --data-binary "@$T\simple\codesystem-simple.json"
foreach ($f in "valueset-all","valueset-active","valueset-inactive","valueset-enumerated","valueset-enumerated-bad","valueset-filter-isa","valueset-filter-property","valueset-filter-regex","valueset-filter-regex2","valueset-filter-regex-prop") {
  curl.exe -X POST "http://localhost:9090/fhir/r4/ValueSet" -H "Content-Type: application/fhir+json" --data-binary "@$T\simple\$f.json"
}
```

## 4. Run the suite

```sh
java -jar validator_cli.jar txTests -tx=http://localhost:9090/fhir/r4 -test-version=1.9.3 -suite=simple-cases -output=./results
```

`-test-version` pins a version of the test suite itself (not a FHIR version).
Omit it to run against `current` (the suite's master branch, which can change
at any time).
