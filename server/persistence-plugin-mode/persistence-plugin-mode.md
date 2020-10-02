# Proposal: Persistence Plugin Model

Author: Wenquan Xing

Last updated: Oct 2020

Discussion at TODO

## Abstract

This document describe the existing & target solution towards supporting multiple storage backends for Temporal server.

## Background

Existing implementation of Temporal server already provide decent abstraction between business logic vs persistence logic. In fact, lots of work have already be done making the SQL persistence layer pluggable, i.e. [link](https://github.com/temporalio/temporal/tree/master/common/persistence/sql/sqlplugin).

Although huge efforts have been dedicated to making the persistence layer standalone and extensible, there are still areas for improvement, e.g. better test coverage with reduced complexity & pluggable NoSQL persistence layer.

## Proposal

### Desired state

Most of the existing high level code / logic structure will be maintained, to limit the potential blast radius as well as for project management.

All plugin model changes will be hidden behind the persistence interface [link](https://github.com/temporalio/temporal/blob/master/common/persistence/persistenceInterface.go).

Plugins will be categorized into 2 buckets: NoSQL and SQL. Please see the component diagram and definition for details:

![image alt text](layout.png)

Definition:

* Business logic
* Persistence interface: persistence APIs for storage of workflow history events; mutable state changes; async tasks.
* Persistence test: overall test logic against generic persistence layer.
* SQL persistence: generic SQL style persistence
  * SQL persistence test: SQL specific tests.
  * SQL persistence common logic: common logic which operates on top of SQL persistence drivers.
  * SQL persistence driver: MySQL; PostgreSQL.
* NoSQL persistence: generic NoSQL style persistence
  * NoSQL persistence test: NoSQL specific tests.
  * NoSQL persistence common logic: common logic which operates on top of NoSQL persistence drivers.
  * NoSQL persistence driver: Cassandra.

### Current state

On NoSQL side, Cassandra is the only supported storage and Cassandra storage layer is *not* onboarded to the desired plugin model. Cassandra storage layer is production ready.

On SQL side, MySQL & PostgreSQL storage layer are implemented. MySQL storage layer is production ready. PostgreSQL storage layer is *not* production ready due to lack of proper testing.

On both sides, existing persistence tests are too generic, and unable to cover necessary test cases.

### Actions

 Below are the action items according to the desired state and current state:

* SQL / NoSQL specific tests and proper generic persistence tests.
* New generic persistence tests with proper mocks to reduce the test complexity.
* Proper rewrite of Cassandra driver layer to adopt the plugin model.
* Deprecation of the current persistence test for better code management.

## Alternatives

Above proposal assumes that Temporal server will continue the path of manual management of SQL / NoSQL queries, with proper manual serialization / deserialization.

Below will also cover an alternative solution which is built on top of ORM lib.

### Object Relational Mapping solution

Object Relational Mapping (ORM) usually provides easy integration with databases if there is solid object model.

When dealing with simple cases, ORM library usually do exactly what is desired with less amount of boilerplate code (e.g. CRUD services).

However, when handling complex cases, developer need to have deep understanding of how the ORM DSL will be translated into SQL / NoSQL queries. This additional layer (ORM library) hides the implementation details, consumes more resources (CPU / mem) and make the query logic harder to understand.

Temporal server persistence layer aims to provide high performance storage capabilities, thus manual management of database queries as well as database specific driver logic provides more benefits.

It is worth pointing out that the number of databases to be supported is limited, currently there are 3 supported databases (Cassandra, MySQL and PostgreSQL). Other databases (Cockroach DB, TiDB) usually provides good compatibilities with either PostgreSQL or MySQL.

References: famous Golang ORMs:

* [gorm](https://github.com/go-gorm/gorm)
* [sqlboiler](https://github.com/volatiletech/sqlboiler)
* [squirrel](https://github.com/Masterminds/squirrel)

References: other databases:

* [Cockroach DB compatibility with PostgreSQL](https://www.cockroachlabs.com/docs/stable/postgresql-compatibility.html)
* [TiDB compatibility with MySQL](https://docs.pingcap.com/tidb/dev/mysql-compatibility)
