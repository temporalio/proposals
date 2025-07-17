# CLI Extensions

## Overview

CLI extensions are separate executables that appear as part of the `temporal` CLI. This is similar to
[`kubectl` plugins](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/) and `git` extensions/commands.

## Usage Examples

### Custom Authenticator

A custom extension can allow

    temporal mycompany login

To set some environment config settings on disk so that successive calls to

    temporal workflow start --type foo --task-queue some-tq --workflow-id foo-id

automatically work.

### Shortcuts for Common Tasks

A custom extension can add something like

    temporal mycompany do-company-thing

And that can do anything programmatically and also get the benefit of having access to the Temporal client. So it could
access some company resource (e.g. a database) and send an update to a workflow with some value.

### Contributions

Custom extensions allow an ecosystem of CLI extensions to form that do not require Temporal oversight. For example

    temporal workflow show-diagram --workflow-id foo-id

Could be an extension that downloads the workflow history and makes a nice visualization of it.

### Cloud CLI

A Temporal Cloud extension will be available (and likely released alongside the traditional CLI) that will allow
cloud-specific operations like:

    temporal cloud namespace list

This can share authentication with the CLI in many ways. It can even support login, so the following two commands could
work well together:

    temporal cloud login --profile cloud
    temporal workflow start --profile cloud --type foo --task-queue some-tq --workflow-id foo-id

These are just usage examples for the purposes of explaining extensions, this may not be what `temporal cloud` extension
looks like when built.

## Runtime Behavior

### Lookup

Extensions are any executables on the `PATH` with `temporal-` prefix. Extension executable names use `-` for each
subcommand and `_` for each dash in the command (but still can be called with an underscore). This is similar to
`kubectl` behavior.

The `PATH` lookup is most-specific to least-specific. For example, running `temporal foo bar-baz qux` will try to match
the following in order:

* `temporal-foo-bar_baz-qux`
* `temporal-foo-bar_baz`
* `temporal-foo`

And the first one found will be executed with all arguments. And since underscores and dashes are the same,
`temporal-foo-bar_baz` executable is called for both `temporal foo bar-baz qux` and `temporal foo bar_baz qux` though
help text only shows the former.

Built-in commands cannot be overridden by extensions, but subcommands can be added to existing commands.

### Discovery and Help Text

Running `temporal --help` (or `temporal help`) _does not_ list extensions. But running `temporal help -a` (or `--all`)
_does_ list all extensions by traversing the `PATH` and getting every `temporal-`-prefixed executable. There is no short
description for any of these extensions, they are simply shown as available external commands. All extensions on the
`PATH` are shown as they are, even if they are multiple commands deep. For example `temporal-foo-bar` and
`temporal-workflow-dosomething-somethingelse` are shown as `foo bar` and `workflow dosomething somethingelse` in the
list respectively, not as just `foo` or implied as part of the `workflow` command.

Extensions on built-in commands are not shown as part of the parent command's help.

Running `temporal help <command sequence>` is treated as `temporal <command sequence> --help`. So the same style of
lookup is performed for extensions.

### Invocation and Flags

Temporal CLI supports arbitrarily ordered flags. So `temporal --address foo workflow start`,
`temporal workflow --address foo start`, and `temporal workflow start --address foo` are all the same. It is still a
subject of active research on whether flags of _parent_ commands can still be placed before the extension command in the
CLI. Regardless, flags of the extension command _must_ come after the extension command because CLI does not know
whether a flag takes an argument or not so it cannot disambiguate. For example, CLI
`temporal --myflag someval1 someval2` cannot determine whether that is `temporal someval1 someval2 --myflag` or
`temporal someval2 --myflag someval1`. So the latter forms must be the forms used for extension-specific flags.

All flags of the parent command _should_ be handled properly by the extension. This means even root-level flags. So for
example, `temporal-foo` _should_ handle root-level flags like `--output`. However, this isn't a _must_ requirement. See
the helper library section for some helpers.

Currently, the only root-level flag that the parent `temporal` process respects when calling an extension is
`--command-timeout` (even though it is still passed along). All other root-level flags are up to the extension to
handle.

Invocation of the extension is done as a subprocess. Stdin, stdout, stderr, exit code, etc are all handled by the
extension and just relayed through the `temporal` process as is. It is an area of active research on whether interrupt
signals can be ignored by the parent `temporal` process to be handled by the subprocess, though that is the goal.

### Helper Library

Built-in commands leverage several helpers to be consistent with the CLI ecosystem. Extension commands should be able to
do the same, within reason, so a helper library will be made available. Originally it was thought that such a helper
library was not needed and extensions could deal with this themselves, but it is clear that there are too many common
flags and situations to have to rewrite logic for.

A package on the existing Go CLI will be made available for use programmatically. The package is
`github.com/temporalio/cli/cliext` and is the only package on the entire library/module that is acceptable for use
programmatically. The existing `github.com/temporalio/cli/temporalcli` package should not be used and may be moved to
`internal` as part of this project.

The CLI module is versioned the same as the CLI binary version. The version of CLI used by users can be different than
the version of CLI module used by extensions, but there may be issues if the CLI version used by a user is newer than
the one used by an extension mostly due to new flags and Temporal client capabilities. Within reason, the CLI team will
try to maintain runtime behavior compatibility with extensions using older forms of this library.

Regarding API compatibility, unlike SDKs, there are no guarantees that `github.com/temporalio/cli/cliext` library API
will remain compatible from one version to the next. CLI team will try its best to retain compatibility, or if it can't,
will try to have clear compilation breaks and release notes. CLI binary versions are not meant to be construed as
related to compatibility of this package which technically means a CLI patch could have a compatibility change in this
library, though CLI team will strive to avoid that at the semver patch level (and only do it at a minor level).

Documentation of this library is in the Godoc of the `github.com/temporalio/cli/cliext` package. Even release notes will
not mention the library unless there is significant reason such as a compatibility break.

The initial implementation of the library will contain the following utilities:

* Structs and Cobra flag sets for root-level flags and Temporal client flags
* Ability to create `*slog.Logger` from root-level flags
* Ability to dial a Temporal client from Temporal client flags
* Utility to create payloads from raw data

Other items can be added as needed. Extensions can/should also use the Go SDK as needed.

There is not a plan to expose a printer at this time, so extensions will have to handle the possible `output` enumerates
of `text`, `json`, `jsonl`, and `none` themselves. This is because the current CLI printer has too many quirks and is
not high quality enough for exposure. It is possible in the future a good printer abstraction can be exposed.

It is an area of active research whether built-in commands will leverage this package or whether both will leverage
common code independently.

It is an area of active research whether the CLI's YAML-based code generation functionality will be made available to
extensions.

#### Use of Environment Configuration

CLI supports environment configuration which, as of this writing, is basically just a way to load client configuration
via config files and environment variables. This is therefore bidirectional. This means that an extension can mutate an
environment configuration file and subsequent built-in commands can use it.

For example, a command may set an API key in a profile of a config file. Then all commands creating Temporal clients
will use that API key.

## Example

### Shell Script

On a Unix-style platform, there can a file named `temporal-workflow-do_thing` on a directory in the `PATH` with the
executable bit set and with the contents (may not be ideal code, just for demo purposes):

```sh
#!/bin/bash

if [ "$1" == "foo" ]; then
    temporal workflow start --type foo --task-queue some-tq --workflow-id foo-id --id-conflict-policy UseExisting
    exit $?
elif [ "$1" == "bar" ]; then
    temporal workflow update --name bar --workflow-id foo-id
    exit $?
else
    echo "Error: Only foo or bar accepted" >&2
    exit 1
fi
```

Now `temporal workflow do-thing foo` and `temporal workflow do-thing bar` work as expected. However, this approach is
usually only good for quick things with limited flexibility. It's not good for general use because it doesn't respect
any of the root-level flags (e.g. `--output json`) or any of the workflow-level flags (e.g. `--namespace`). Proper
extensions should likely use the helper library.

### Go-based

TODO