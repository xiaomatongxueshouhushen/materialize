# Copyright Materialize, Inc. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

# Verify the error message is useful when a schema is not present in the
# registry.

! CREATE SOURCE noexist
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-noexist-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM
fetching latest schema for subject 'testdrive-noexist-${testdrive.seed}-value' from registry: subject not found

$ set schema-v1={
    "type": "record",
    "name": "envelope",
    "fields": [
      {
        "name": "before",
        "type": [
          {
            "name": "row",
            "type": "record",
            "fields": [
              {"name": "a", "type": "long"}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] }
    ]
  }

$ set schema-v2={
    "type": "record",
    "name": "envelope",
    "fields": [
      {
        "name": "before",
        "type": [
          {
            "name": "row",
            "type": "record",
            "fields": [
              {"name": "a", "type": "long"},
              {"name": "b", "type": "long", "default": 42}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] }
    ]
  }

$ kafka-create-topic topic=data

$ kafka-ingest format=avro topic=data schema=${schema-v1} publish=true timestamp=1
{"before": null, "after": {"a": 1}}

$ kafka-ingest format=avro topic=data schema=${schema-v1} publish=true timestamp=2
{"before": null, "after": null}

> CREATE MATERIALIZED SOURCE data_v1
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM

> SELECT * FROM data_v1
a
---
1

$ kafka-ingest format=avro topic=data schema=${schema-v2} publish=true timestamp=3
{"before": null, "after": {"a": 2, "b": -1}}

$ kafka-ingest format=avro topic=data schema=${schema-v2} publish=true timestamp=4
{"before": null, "after": null}

> CREATE MATERIALIZED SOURCE data_v2
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM

> SELECT * FROM data_v1
a
---
1
2

> SELECT * FROM data_v2
a b
----
1 42
2 -1

$ set key-schema-missing={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "b", "type": "long"}
    ]
  }

$ set key-schema-wrong-type={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "a", "type": "int"}
    ]
  }

$ set valid-key-schema={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "a", "type": "long"}
    ]
  }

$ kafka-create-topic topic=missing-data

$ kafka-ingest format=avro topic=missing-data schema=${schema-v1} key-schema=${key-schema-missing}
  publish=true timestamp=1
{"before": null, "after": {"a": 1}}

$ kafka-ingest format=avro topic=missing-data schema=${schema-v1} key-schema=${key-schema-missing}
  publish=true timestamp=2
{"before": null, "after": null}

! CREATE SOURCE data_v3
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-missing-data-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM
Value schema missing primary key column: b

$ kafka-create-topic topic=mismatched-data

$ kafka-ingest format=avro topic=mismatched-data schema=${schema-v1} key-schema=${key-schema-wrong-type}
  publish=true timestamp=3
{"before": null, "after": {"a": 1}}

$ kafka-ingest format=avro topic=mismatched-data schema=${schema-v1} key-schema=${key-schema-wrong-type}
  publish=true timestamp=4
{"before": null, "after": null}

! CREATE SOURCE data_v3
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-mismatched-data-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM
key and value column types do not match

$ kafka-ingest format=avro topic=data schema=${schema-v1} key-schema=${valid-key-schema}
  publish=true timestamp=5
{"before": null, "after": {"a": 1}}

$ kafka-ingest format=avro topic=data schema=${schema-v1} key-schema=${valid-key-schema}
  publish=true timestamp=6
{"before": null, "after": null}

> CREATE MATERIALIZED SOURCE data_v3
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE DEBEZIUM

> SELECT * FROM data_v3
a
---
1 42
1 42
2 -1
