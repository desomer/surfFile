# super_schema_dsl

Package partagé entre `super_designer` et `super_spec_forge` fournissant :
- `JsonNode`, `JsonModel`, `JsonBrowser` (`json_browser.dart`) ;
- `Yaml2JsonSchemasParser` (`yaml2jsonschemas_parser.dart`) ;
- `RepositorySchemaModel`, `patchYamlSchemaSnapshot` (`repository_schema_model.dart`).

Un hôte peut fournir des types de référence externes à `Yaml2JsonSchemasParser`
via `externalTypes`. Sans cette option, les références inconnues restent rejetées.
