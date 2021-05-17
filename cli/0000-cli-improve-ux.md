- Start Date: 2020-05-29
- RFC PR:
- Issue:

# Summary

The current CLI was designed seemingly for the internal use and the good UX wasn't among the top priorities in the initial implementation.
The UX lacks in the number of areas such as consistency, semantics, commands discoverability, no integration with bash/zsh, few flags are global when they arguably shouldn't be, no default configs file support, UI that could do a better job helping users to "scan" though the `help` output

### Goals

- Improve commands discoverability
- Integrate with Bash/zsh
- Support default configs file
- Standardize wording
- Rework the short versions of commands
- Bring consistent schema for operations on multiple entities
- Use hyphens instead of underscores
- Lower priority: Improve help command output/UI

### Non-goals

- Creating any kind of new CLI business logic

# Detailed design

### Improve commands discoverability

Problem: As a user i want to easily find commands i'm interested in. Less nesting leads to easier discovery.

Commands discoverability can be improved by limiting CLI commands to a maximum of 2 levels nesting.

Before 
``` bash
tctl workflow activity complete {flags}
```
After 
``` bash
tctl activity complete {flags}
```

### Integrate with Bash/zsh

Problem: As a user i will benefit from bash/zsh auto-suggestions, auto-completion and suggestions for mistyped commands.

Before

- Users have to type entire commands and flags

After

- Pressing Tab when a command/option is partially typed and there is only one candidate should auto-complete the command/option.

- Pressing Tab when there are multiple candidates should output the candidates and allow to continue typing

- Making a typo in a command/option should output candidates for what user possibly meant to type

### Support default configs file

Problem: As a user i want to be able to change the defaults of some flags, such as the default namespace
Create a default config file that CLI will look into to use in commands.
If the user passes an option explicitly, ignore the defaults from the config file
For start, support the following default flags through the file:
 - `--namespace`

Add `config` command to open the config in default editor

 Use XDG-spec to locate the config file:
 ~/.config/tctl on Unix
 %LOCALAPPDATA%\tctl on Windows

### Standardize wording

Problem: As a user i want the CLI API to be consistent, so that it is easier to remember commands and less chances to mix up the words

|Word	|Meaning	|Similar words	|Example	|To be deprecated, example	|
|---	|---	|---	|---	|---	|
|	|	|	|	|	|
|create (c)	|create a resource	|register, add, put	|`tctl namespace create <id>`	|`tctl --namespace <id> namespace register`	|
|run (r)	|Create and execute a resource	|start, launch, invoke,
execute	|`tctl workflow run --detach --input "{}"`	|`tctl workflow start -- Also see current Execute Usage in protos`	|
|update (u)	|update resource fields specified by flags	|change	|`tctl namespace update <id> —owner-email buzz@mail.com`	|	|
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

### Short versions of commands and flags

Short versions are meant for advanced users. No need to preserve semantic meaning by keepig few extra letters. 
Shortening the commands/flags should make them actually short: 1-2 characters. 
One-character flags should only be used for commonly used flags 

### Bring consistent schema for operations on multiple entities

Allow operations to run on multiple entities by providing multiple identifiers or by filtering entities by a query
Running on single entity
``` bash
tctl workflow terminate {flags} id1
```

Running on multiple entities by providing a list of arguments
``` bash
tctl workflow terminate {flags} id1 id2 id3
```

Running on multiple entities by providing a list of flags
``` bash
tctl workflow terminate {flags} -id id1 -id id2 -id id3
```

Running on multiple entities by providing providing filter query
``` bash
tctl workflow terminate {flags} --filter 'started > 1 day ago'
```

### Use hyphens instead of underscores

Problem: Users typically expect hyphens and don't expect having to switch to underscores when typing flags 

Replaces all underscores used in commands and flags as delimiters with hyphenes

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

In the help command output, make the command and option names stand out from the rest of text. This can be achieved by adding color or bold effects. Add command examples in help.
NO_COLOR, TERM=dumb env variables or --no-color should disable coloring.

Help command variants:
- tctl help
- tctl -help
- tctl --help
- tctl -h
- tctl --help

Help should work for sub-commands, ex:
- tctl workflow help

All commands should also have concrete examples of usage in the help output:
`tctl namespace update help`
Should have an example in the output, among the lines of 
```
...
{help output mentioning arguments, flags etc..}
... then the help is followed by
Examples
$ tctl namespace update --namespace default --description 'my namespace new description'
Namespace default is successfully updated.
```

Involve/fully deligate help section to documentation team?

### Show loading indicators

Problem: A number of commands may take time to execute and show output, leaving users confused

Show a loading animation indicator where applicable. The indicator should only be applied if the output medium is a terminal (stdout is connected to tty).

Provide a separate flag and environment variable to allow users to disable the indicator. Lastly this should be possible to configure in the default configs file.

Target to make the cli immediate and responsive.

### Improve output UX

Problem: printing lists of data in a form of a table or json is a) limited in flexibility modifying the columns to ouput is currently hardcoded to column per dedicated flag ex  --print_memo b) UX is a bit noisy such as it always prints new table headers when paginating, borders are always shown, single entity row may spill to the next rows and break the tables etc 

Provide --columns flag so users can customize the fields to output. Show only few columns by default. 
Truncate rows if they don't fit in the screen. Provide --no-truncate to disable that.
Provide --no-headers to disable Table headers
Do not draw borders in a table as they are noisy.
Allow output in csv

### Support parsing of output (grep-parseable, json parsing using jq)
Problem: majority of tctl commands do not consider grep, jq and other tools that users may want to use when outputting results

Structure outputs so it would be easy to pipe them into `grep`, `jq`, `wc`, `less` or redirect output to a file.
Json output (--json flag) should be possible to process using jq.
Use strerr for messages that you still want to show in a terminal even if the output is redirected to a file. For example when printing errors

Adding `--plain` flag may help if human-readability still makes it too hard to make the output also pipable into other tools. Then this flag can be used to print machine-readable output.

# Sources for the spec
https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46
https://devcenter.heroku.com/articles/cli-style-guide
https://clig.dev/

# Drawbacks

The proposal changes the interaction with Temporal CLI. Existing users who have already learned the current CLI will need to check out the changes

# Adoption strategy

Make annoucements about all of the CLI changes when we release them. Update the CLI documentation. Expect some users to learn from the CLI itself if they miss the annoucements/checking docs
