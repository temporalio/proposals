- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Use hyphens instead of underscore

Currently all flags use underscore as a delimiter between words. Ex. `--workflow_id`. Using hyphens is a much more established pattern, plus it requires pressing only one key instead of two. Change all occurences of underscores in flags to hyphens.

Before: `tctl workflow describe --workflow_id myworkflow`

After:  `tctl workflow describe --workflow-id myworkflow`
