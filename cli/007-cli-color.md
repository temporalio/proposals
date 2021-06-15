- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Better coloring

Good usage of coloring can help users to read the output and direct attention to the most interesting parts.

- Standartize the colors used in printing
- Work through commands and improve the coloring
- add a flag `--no-color` to disable coloring alltogether
- low priority: colorize command and flag names in `--help` output
- low priority: add built-in coloring of `--json` output. Piping into `jq` can be used by users as an alternative so low priority.
