- Start Date: 2021-08-22
- RFC PR:
- Issue:

### Multi configurations

Support creating and switching between multiple configurations

Users may have multiple Temporal service set ups (development, production, ..) with their own respective mTLS configs, namespaces, address etc. Current implementation of tctl config feature only supports setting a single set of configurations.

To make it easy for users to switch between set ups, add support for multiple configurations (contexts) and switching between them.

Syntax to activate a context:

```bash
$ tctl config set-context <name>
Active context: <name>
```

If the context doesn't yet exist, create it and set as active

```bash
$ tctl config set-context <new>
Context <new> doesn't exist, adding..
Active context: <name>
```

Split configuration keys into 1) context scope - residing in a scope of a specific context 2) global scope - out of any specific context

Global scope keys:

- "active" - name of active context
- "contexts" - sequence of contexts
- "alias" - sequence of command aliases

Context scope keys:

- namespace
- address
- data-converter-plugin
- tls-ca-path
- tls-key-path
- tls-cert-path
- tls-server-name
- tls-disable-host-verification

Example of context aware configuration file:

```yml
active: development
contexts:
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
version: next
```
