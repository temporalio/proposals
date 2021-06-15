- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Show loading indicators in long running commands

Some commands may take time to execute until showing an output or an error (typically context timeout). This makes tctl feel unresponsive and slow, leaving users confused.

Show a loading and progress indicators where applicable. The indicator should only be applied if the output medium is a terminal (stdout is connected to tty). Provide a separate flag and environment variable to allow users to disable the indicator.

Target to make the cli immediate and responsive.
