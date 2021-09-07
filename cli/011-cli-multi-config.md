- Start Date: 2021-08-22
- RFC PR:
- Issue:

### Configuring multiple environments

##### Problem

Users may have multiple Temporal service environments (development, production, ..) with their own respective mTLS configs, namespaces, address etc. Current implementation of tctl config feature only supports configuring a single environment and doesn't help at quickly switching between multiple.

##### Proposal

To make it easy for users to switch between environments, allow configuring multiple instead of just one and provide command to switch between them.

Syntax to activate environment configs:

```shellsession
$ tctl config use-environment <name>
Active environment: <name>
```

If the environment doesn't yet exist in config, create it and set as active

```bash
$ tctl config use-environment <new>
Environment <new> record doesn't exist, adding..
Active environment: <name>
```

Split configuration keys into 1) environment scope - keys residing in a scope of specific environments 2) global scope - out of any specific environment

Global scope keys:

- "active" - name of active environment
- "environments" - sequence of environments
- "alias" - sequence of command aliases

Environment scope keys:

- namespace
- address
- data-converter-plugin
- tls-ca-path
- tls-key-path
- tls-cert-path
- tls-server-name
- tls-disable-host-verification

##### Using environment per command --environment

Add a global flag `--environment <name>` that will use specific environment when running a command, but not set it as active in config.  

Example:
```bash
$ tctl --environment cluster-1 workflow list
```

##### Example of environment aware configuration file:

```yml
active: development
environments:
  - name: development
    namespace: default
    address: 127.0.0.1
    port: 7023
  - name: cluster-1
    namespace: accounting
    address: 10.x.x.x
    port: 7023
alias:
  - key: wl
    value: workflow list
```
