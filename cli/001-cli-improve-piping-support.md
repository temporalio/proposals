- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Support better piping of output 
Problem: currently piping the output into other tools is not well supported. For example utilities such as `grep`, `wc`, `jq` may work with very limited set of commands / in limited functionality. 

Structure outputs so it would be easy to pipe it into common utilities. 

To achieve that:

 - `wc`, `more` support: integrate output with `less` cmd by default if it's available in the OS. If `less` is not found, create and use builtin functiniality to output all available rows immediately (similar to how `cat` behaves).
 
 Examples: 
 ``` bash
 tctl workflow list --open --all | wc -l
 ```
 ``` bash
 tctl workflow list --all | more
 ```
 
 - `grep` support: add a --format view to output data as cards, where each row follows format `{field name}: {field value}`
 
 Examples:
 ``` bash
 tctl workflow list --format card --all | grep WorkflowId
 ```
 - `jq` support: json output (`--json` flag) should be possible to process using jq

Examples:
``` bash
tctl workflow list --json | jq '.execution'
```
