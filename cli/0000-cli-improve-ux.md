- Start Date: 2020-05-29
- RFC PR:
- Issue:

# Summary

The current CLI was designed seemingly for the internal use and the good UX wasn't among the top priorities in the initial implementation.
The UX lacks in the number of areas such as consistency, semantics, commands discoverability, no integration with bash/zsh, few options are global when they arguably shouldn't be, no default configs file support, UI that could do a better job helping users to "scan" though the `help` output  

### Goals

- Improve commands discoverability
- Integrate with Bash/zsh
- Support default configs file
- Standardize wording
- Reimplement the short versions of commands
- Bring consistent schema for operations on multiple entities
- Use hyphens instead of underscores
- Lower priority: Improve help command output/UI

### Non-goals

- Creating any kind of new CLI business logic
- Refactoring or improving CLI code base

# Detailed design

### Improve commands discoverability

Problem: As a user i want to easily find commands i'm interested in. Less nesting leads to easier discovery.

Commands discoverability can be improved by limiting CLI commands to a maximum of 2 levels nesting.

Before 
``` bash
tctl workflow activity complete {options}
```
After 
``` bash
tctl activity complete {options}
```

### Integrate with Bash/zsh

Problem: As a user i will benefit from bash/zsh auto-suggestions, auto-completion and suggestions for mistyped commands.

Before

- Users have to type entire commands and options

After

- Pressing Tab when a command/option is partially typed and there is only one candidate should auto-complete the command/option.

- Pressing Tab when there are multiple candidates should output the candidates and allow to continue typing

- Making a typo in a command/option should output candidates for what user possibly meant to type

### Support default configs file

Problem: As a user i want to be able to change the defaults of some options, such as the default namespace
Create a default config file that CLI will look into to read them and use in commands.
If the user passes an option explicitly, ignore the defaults from the config file
For start, support the following default options through the file:
 - `--namespace`

### Standardize wording

Problem: As a user i want the CLI API to be consistent, so that it is easier to remember commands and less chances to mix up the words

|Word	|Meaning	|Similar words	|Example	|To be deprecated, example	|
|---	|---	|---	|---	|---	|
|	|	|	|	|	|
|create (c)	|create a resource	|register, add, put	|`tctl namespace create <id>`	|`tctl --namespace <id> namespace register`	|
|run (r)	|Create and execute a resource	|start, launch, invoke,
execute	|`tctl workflow run --detach --input "{}"`	|`tctl workflow start -- Also see current Execute Usage in protos`	|
|update (u)	|update resource fields specified by options	|change	|`tctl namespace update <id> —owner-email buzz@mail.com`	|	|
|describe (d)	|Output resource info	|show	|`tctl workflow describe <id>`	|	|
|login	|	|	|`tctl login --username buzz@mail.com --pasword 123`	|	|
|list (ls)	|output a table of resource items	|listall, ps, show, get	|`tctl workflow list`	|`tctl workflow listall`	|
|watch (w)	|continiously output the logs as the workflow/process is running	|observe	|	|	|
|terminate (t)	|	|kill, stop	|	|	|
|reset	|	|	|`tctl workflow reset <id>`	|	|
|request	|	|	|`tctl workflow request-cancel <id>`	|	|
|respond	|respond to an outstanding request	|	|	|	|
|remove (rm)	|mark resource as removed (if applicable)	|delete, uninstall, clear	|	|	|
|uri	|Uri value	|address, link, resource	|	|	|

### Rethink the short versions of commands

Short versions are meant for advanced users. No need to preserve semantic meaning by keepig few extra letters. Shortening the commands/options should make them actually short: 1-2 characters.

### Bring consistent schema for operations on multiple entities

Allow operations to run on multiple entities by providing multiple identifiers or by filtering entities by a query
Running on single entity
``` bash
tctl workflow terminate {options} id1
```

Running on multiple entities by providing a list of ids
``` bash
tctl workflow terminate {options} id1 id2 id3
```

Running on multiple entities by providing providing filter query
``` bash
tctl workflow terminate {options} --filter 'started > 1 day ago'
```

### Use hyphens instead of underscores

Problem: Users typically expect hyphens and don't expect having to switch to underscores when typing options 

Replaces all underscores used in commands and options as delimiters with hyphenes

Before:
``` bash
tctl activity complete --workflow_id <uuid>
 ```
After
``` bash
tctl activity complete --workflow-id <uuid>
```

### Improve help command output/UI

Problem: Users tend to scan instead of read. They skip large chunks of information

In the help command output, make the command and option names stand out from the rest of text. This can be achieved by either adding color or bold effect

# Drawbacks

The proposal changes the interaction with Temporal CLI. Existing users who have already learned the current CLI will need to check out the changes

# Adoption strategy

Make annoucements about all of the CLI changes when we release them. Update the CLI documentation. Expect some users to learn from the CLI itself if they miss the annoucements/checking docs