- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Commands auto-completion
Support auto-completion of commands in bash. Lesser priority - zsh.

- Pressing Tab when a command/flag is partially typed and there is only one candidate should auto-complete it.
- Pressing Tab when there are multiple candidates should output the candidates and allow to continue typing.

Add a command `completion` to output the completion script. Command name and behavior is taken from similar cases in `kubectl` and `gh` to "build on potential user's expected knowledge" per UNIX philosophy
