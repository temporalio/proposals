- Start Date: 2021-08-22
- RFC PR:
- Issue:

### Simplify admin commands usage

Problem: As of today admin commands are way too complex to use as they require passing DB connection flags in addition to command specific flags.

##### tctl

Use Temporal service Frontend Admin API and remove direct DB connection from the tctl admin commands.
Implement new admin commands in github.com/temporalio/tctl repo.

##### Admin API

Temporal Frontend admin API misses a number of interfaces for tctl admin commmands to work. These APIs will need to be added.

##### Prioritization voting

To understand what exact APIs to add first, please upvote/comment on the commands that are useful to you. If there is any functionality that you would like to be added, please comment proposing it.

| Commmand      | Sub-command              | Accesses DB? | Description                                                                                |
| ------------- | ------------------------ | ------------ | ------------------------------------------------------------------------------------------ |
| workflow      | show                     | yes          | show workflow history                                                                      |
| workflow      | describe                 | no           | Describe internal information of workflow execution                                        |
| workflow      | refresh_tasks            | no           | Refreshes all the tasks of a workflow                                                      |
| workflow      | delete                   | yes          | Delete current workflow execution and the mutableState record                              |
| shard         | describe                 | yes          | Describe shard by Id                                                                       |
| shard         | describe_task            | yes          | Describe a task based on task Id, task type, shard Id and task visibility timestamp        |
| shard         | list_tasks               | yes          | List tasks for given shard Id and task type                                                |
| shard         | close_shard              | no           | close a shard given a shard id                                                             |
| shard         | remove_task              | no           | remove a task based on shardId, task type, taskId, and task visibility timestamp           |
| history_host  | describe                 | no           | Describe internal information of history host                                              |
| history_host  | get_shardid              | no           | Get shardId for a namespaceId and workflowId combination                                   |
| namespace     | list                     | yes          | List namespaces                                                                            |
| namespace     | register                 | no           | Register workflow namespace                                                                |
| namespace     | update                   | no           | Update existing workflow namespace                                                         |
| namespace     | describe                 | no           | Describe existing workflow namespace                                                       |
| namespace     | get_namespaceidorname    | yes          | Get namespaceId or namespace                                                               |
| elasticsearch | catIndex                 | no           | Cat Indices on Elasticsearch                                                               |
| elasticsearch | index                    | no           | Index docs on Elasticsearch                                                                |
| elasticsearch | delete                   | no           | Delete docs on Elasticsearch                                                               |
| elasticsearch | report                   | no           | escribe pollers and status information of task queue                                       |
| taskqueue     | list_tasks               | yes          | List tasks of a task queue                                                                 |
| membership    | list_gossip              | no           | List ringpop membership items                                                              |
| membership    | list_db                  | yes          | List cluster membership items                                                              |
| cluster       | add-search-attributes    | no           | Add custom search attributes                                                               |
| cluster       | remove-search-attributes | no           | Remove custom search attributes metadata only (Elasticsearch index schema is not modified) |
| cluster       | get-search-attributes    | no           | Show existing search attributes                                                            |
| cluster       | describe                 | no           | Describe cluster information                                                               |
| cluster       | metadata                 | no           | Show cluster metadata                                                                      |
| dlq           | read                     | no           | Read DLQ Messages                                                                          |
| dlq           | purge                    | no           | Delete DLQ messages with equal or smaller ids than the provided task id                    |
| dlq           | merge                    | no           | Merge DLQ messages with equal or smaller ids than the provided task id                     |
| db            | scan                     | yes          | scan concrete executions in database and detect corruptions                                |
| db            | clean                    | yes          | clean up corrupted workflows                                                               |
| decode        | proto                    | no           | Decode proto payload                                                                       |
| decode        | base64                   | no           | Decode base64 payload                                                                      |
