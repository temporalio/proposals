- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Show spinner in long running commands

Some commands may take time to execute until showing an output or an error (typically context timeout). This makes tctl feel unresponsive and slow, leaving users confused.

Show a spinner or progress bar where applicable.

The spinner/progress bar should only be applied if the output medium is a terminal (stdout is connected to tty). 
Add a flag `--no-progress` that disables spinner (similar to [npm --no-progress](https://github.com/npm/npm/issues/8704#issuecomment-158222250) )

Target to make the cli immediate and responsive.
