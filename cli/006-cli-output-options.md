- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Improve commands output UX and rendering options

Current Issues and improvement proposals:

#### - Many commands do not support switching between Table and JSON views.

In places where we retrieve and print entity objects, support changing how the objects are printed through `--output` flag that accepts the following values:
- `--output table` # default for most commands
- `--output json`
- `--output card` # new view

For arrays of objects, usually prefer Table view as the default. Implement the proposal by creating a unified rendering utility.

#### - All commands do not support printing data in a form of cards (`{field name}: {field value}` per row), which is especially useful in combination with `grep` or when describing a single object.

Add `--output card` key that will print entity object in a format `{field name}: {field value}`.
``` bash
tctl workflow list --output card | grep WorkflowId
```

#### - Limited support for changing the columns/fields in Table view. Only specific fields are explicitly supported through flags, ex. `--print_memo`.

Proposal: Add `--columns` flag so users can customize the columns to output in Table/Card. The flag should accept comma separated list of field names. Not passing a value into `--columns` or passing a wrong field name should print an error message plus all of the available fields.  
``` bash
tctl workflow list --columns "Execution.RunId, searchAttributes"
```

#### - Output is often noisy, single entity row may spill to the next rows and break the tables.

Change the list commands to output 3-5 columns/fields by default. Add a special case value `long` for `--columns` flag that will add few more of the ~most important fields. This behavior is similar to `nushell`'s `ls --long` flag
``` bash
tctl workflow list --columns long
```
