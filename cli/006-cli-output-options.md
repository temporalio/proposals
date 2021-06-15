- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Improve commands output UX and rendering options

- many commands do not support switching between Table and JSON views. ~All commands to not support printing data in a form of cards (`{field name} {field value}`), which is especially useful for `grep`.

Proposal:

- limited support for changing the columns/fields in Table view. Only specific fields are explicitly supported through flags, ex. `--print_memo`.

- Output is sometimes noisy, single entity row may spill to the next rows and break the tables.

Change the list commands to output 3-5 columns/fields by default. Add `--details` flag that will add few more of the ~most important fields. This behavior is similar to `nushell`'s `ls --long` flag

Example:
``` bash
tctl workflow list --details
```

Add `--field` flag so users can customize the fields to output in Table/Card (can be passed ). Add `--fields` flag to examine and print all available field names for --field input. If a field passed with `--field` is not found, then notify the user and print the result of `--fields` as a suggestion. 

Example:
``` bash
tctl workflow list --field Execution.RunId --field searchAttributes
```
