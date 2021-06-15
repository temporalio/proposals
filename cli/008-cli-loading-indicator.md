- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Show loading indicators

A number of commands may take time to execute until showing any output, leaving users confused.

Show a loading animation indicator where applicable. The indicator should only be applied if the output medium is a terminal (stdout is connected to tty). Provide a separate flag and environment variable to allow users to disable the indicator. Lastly this should be possible to configure in the default configs file.

Target to make the cli immediate and responsive.
