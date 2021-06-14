- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Config file for tctl defaults
As a user i want to be able to change the defaults of some flags, such as the default namespace.
Support configuring some of the tctl defaults through a configuration file. 

Add `config` top level command that should allow setting and reading specific config options

 Use XDG-spec to locate the config file:
 
 `~/.config/tctl` on Unix
 
 `%LOCALAPPDATA%\tctl` on Windows

For start, support the equivalents of the following tctl flags:
 - Namespace name `--namespace`
 - Temporal frontend service address `--address`
 - Data converter plugin path `--data-converter-plugin`
 - RPC context timeout `--context_timeout`
