# External Client Configuration

Notes for this proposal:

* Everything is subject to change both during proposal time and afterwards during implementation.
* For each place a decision is made, a "💭 Why X? ..." aside is present explaining why.
* For each place an open question exists, a "❓ X?" exists to ask it.

## Overview

There are many ways to access Temporal programmatically including CLI, SDK, and other components that leverage those
such as samples and Terraform providers.

Temporal needs a way for users to provide client configuration without hardcoding in CLI arguments or SDK options. This
will allow code to seamlessly switch between profiles such as between a dev-server and cloud. The same configuration
must work across all SDKs/CLIs.

### Why?

What are the reasons for building this?

* Users want to switch environments without changing their code, but today they cannot.
* Our samples should be able to be run on multiple environments including cloud, but today they are localhost only.

### Goals

* Common, well-specified/type-safe configuration format usable by Temporal tooling for client options and usable
  manually by advanced users
* Implementation in all Temporal SDKs for reading and writing of this configuration
* All Temporal CLI/SDKs updated to have easy client creation using this configuration
* Common on-disk location in every platform for reading/writing this format
* Ability to provide environment variables to represent values in the configuration
* Well-specified hierarchy for on-disk overridable by environment variables overridable by in-CLI/SDK values
* 0 new dependencies in SDKs
  * 💭 Why?
    * Dependencies in our SDKs subject our users to these dependencies and their version constraints, so we should avoid
      this as much as possible.
  * ❓ Can we just have an "extension" that has new dependencies?
    * Yes, but ideally users don't have to add dependencies on extension libraries just to get this functionality.
* Profile names within the configuration
  * 💭 Why?
    * It is common in configurations like this to want to be able to share a single file with many configurations.

### Future Goals

None identified at this time. The goals are simple enough for the MVP and the non-goals are ones we never want.

### Non-goals

* Common format for declarative workers, schedules, etc. This is only for client options.
* File-based hierarchy. We don't need many levels of file merging for these options.
* Use external configuration by default in SDKs (it is default in CLI and samples). Users need to opt-in to this for
  compatibility and clarity reasons (but it is of course easy).

### High-level Usage Examples

#### Simple Switch from Local to Cloud

Similar to `temporal env` today, you can use the CLI to manage configurations with `temporal config`.

For example, say you had this Go code for starting a workflow:

```go
options, err := client.LoadOptionsFromConfig("default")
if err != nil {
  return err
}
cl, err := client.Dial(options)
run, err := cl.ExecuteWorkflow(
  ctx,
  client.StartWorkflowOptions{ID: "my-id", TaskQueue: "my-task-queue"},
  MyWorkflow,
)
```

By default this only works on `localhost:7233` with namespace `default` when you run it. But if you were a cloud user,
you could do this in environment variables for mTLS auth:

    export TEMPORAL_ADDRESS=my-ns.a1b2c.tmprl.cloud:7233
    export TEMPORAL_NAMESPACE=my-ns.a1b2c
    export TEMPORAL_TLS_CLIENT_CERT_PATH=path/to/my/client.pem
    export TEMPORAL_TLS_CLIENT_KEY_PATH=path/to/my/client.key

Now running the same code again unmodified will run against cloud. You can do this same thing with config instead of
environment variables:

    temporal config set --key address --value my-ns.a1b2c.tmprl.cloud:7233
    temporal config set --key namespace --value my-ns.a1b2c
    temporal config set --key tls.clientCertPath --value path/to/my/cert.pem
    temporal config set --key tls.clientKeyPath --value path/to/my/cert.key

Now running the same code again unmodified will run against cloud. Or in a Temporal future with API keys and a
known/fixed API endpoint:

    temporal config set --key cloudApiKey --value my-api-key

And that would be all that is needed (but that is a future scenario, note `cloudApiKey` is not a defined key today, but
`apiKey` is, but you have to put in the `address` and `namespace` still).

#### Profile Switching

Similar to AWS tooling and other tools, you can have profiles. So you can have:

    temporal config set --profile dev --key address --value my-dev-ns.a1b2c.tmprl.cloud:7233
    temporal config set --profile dev --key namespace --value my-dev-ns.a1b2c
    temporal config set --profile dev --key tls.clientCertPath --value path/to/my/dev-cert.pem
    temporal config set --profile dev --key tls.clientKeyPath --value path/to/my/dev-cert.key

For dev and then in production, this might exist:

    temporal config set --profile prod --key address --value my-prod-ns.a1b2c.tmprl.cloud:7233
    temporal config set --profile prod --key namespace --value my-prod-ns.a1b2c
    temporal config set --profile prod --key tls.clientCertPath --value path/to/my/prod-cert.pem
    temporal config set --profile prod --key tls.clientKeyPath --value path/to/my/prod-cert.key

Or alternatively it could be a fixed file that that creates or environment variables or whatever.

Now a simple setting of `TEMPORAL_PROFILE` environment to `dev` or `prod` will switch connectivity (or `--profile` on
CLI or the string in the SDK if you don't want to use environment variable).

#### Manually Working with Configuration

If a user wanted to hand-write a configuration, they can have `my-file.json` like:

```json
{
  "profiles": {
    "default": {
      "address": "my-host:7233",
      "namespace": "my-namespace"
    }
  }
}
```

* This is the same format used by the CLI and the CLI can even be used to edit this file.
* `TEMPORAL_CONFIG_FILE` env var can point to this file or the config file can be manually set in the CLI/SDK.
* There is a type safe contract this file conforms to for anyone wanting to work with it programmatically.
* All SDKs accept the type safe model this file represents if users would rather provide config that way.

#### Possible UI Creation Flow

When a user creates an API key, the completion screen can provide a download of the config file that will have the
address, namespace, and API key set. So it can say something like:

```
API key is created, make sure you copy it here because it is not stored:

    <some long api key string>

Alternatively, you can download it as a configuration file:

    <some button or something that downloads a file name temporalio.json>

You can place this configuration file in the default place used by CLIs/SDKs:

* macOS - `$HOME/Library/Application Support/temporalio/temporal.json`
* Windows - `%AppData%/temporalio/temporal.json` (often `C:\Users\<myuser>\AppData\Roaming\temporalio\temporal.json`)
* Linux - `$HOME/.config/temporalio/temporal.json`

This will be automatically consumed by the SDKs/CLI. This file can also be put anywhere else and `TEMPORAL_CONFIG_FILE`
environment variable can be set to point to it.
```

#### Possible CLI Creation Flow

Assuming cloud support is present in `temporal` CLI, you can have the normal certificate generation steps, e.g.

```
temporal cloud gen ca ...
temporal cloud gen leaf ...
temporal cloud namespace add-accepted-client-ca ...
```

And that last step can by default set a `temporal-cloud` profile in the configuration with the address, namespace, and
mTLS certificates. So now all you have to do to use cloud in CLI is either `--profile temporal-cloud` or set
`TEMPORAL_PROFILE=temporal-cloud` environment variable. Granted you may want better certificate management than that and
whether this is done by default can be discussed, but the idea is the same.

## Specification

### Values and File Format

* The format is a JSON object with the following fields:
  * `profiles` - Object with keys as profile names. The default profile should be named `default`.
    * `<name>` - Profile object with configuration values. Profile names are case-insensitive. 💭 Why? They are needed
      for environment variables which are case insensitive. It is a validation error to have a config file with two
      separately-cased profile names that are equal case-insensitively.
      * `address` - Client address, aka gRPC "host:port". This cannot be a URL, it must be `host:port`.
      * `namespace` - Client namespace.
      * `apiKey` - Client API key.
      * `tls` - A boolean (true is same as empty object) _or_ an object. Note the default for this value is dependent
        upon other settings here. 💭 Why? We regret not making TLS the default in the past, so we will make it default
        if `apiKey` is present. If TLS is an object, it can have the following possible fields:
        * `clientCertPath` - File path to mTLS client cert. Mutually exclusive with `clientCertData`.
        * `clientCertData` - Cert data. Mutually exclusive with `clientCertPath`.
        * `clientKeyPath` - File path to mTLS client key. Mutually exclusive with `clientKeyData`.
        * `clientKeyData` - Key data. Mutually exclusive with `clientKeyPath`.
        * `serverCaCertPath` - File path to server CA cert. Mutually exclusive with `serverCaCertData`.
        * `serverCaCertData` - CA cert data. Mutually exclusive with `serverCaCertPath`.
        * `serverName` - Override SNI name when connecting to server.
        * `disableHostVerification` - Boolean to disable verifying TLS server host. May not be available in all Temporal
          clients. 💭 Why? Not all SDKs offer this feature today.
      * `codec` - Remote codec information to use for all encoding/decoding of payloads. May not be available in all
        Temporal clients. 💭 Why? Not all SDKs allow use of a remote codec today.
        * `endpoint` - Endpoint to the remote codec.
        * `auth` - Authorization header for the remote codec.
      * `grpcMeta` - Object representing HTTP headers. Values must be strings for now (can discuss arrays later).
        ❓ Should we call this `headers`? We do in some cases and not others.
  * 💭 Why JSON?
    * Because YAML and TOML and others require a dependency in our SDKs. AWS for example has a homegrown INI-ish
      implementation they have had to build in to every language.
    * We accept that while JSON is technically human-authorable, it's not as easy as other formats. This is acceptable
      since we will be providing tooling to mutate the config.
    * ❓ Should we consider "json with comments" and some kind of very basic pre-parser in each language that strips
      them? This could come later and not part of MVP.
* This whole format will be defined in proto in the API repo in the `sdk` package.
  * 💭 Why?
    * Clear, centralized contract.
    * Our SDKs already use proto dependency and this gives them stable JSON without requiring separate JSON dependency.
    * Users can use the proto tooling to read/write configs programmatically since they are just proto JSON.
* Do not validate that all keys are known in the file.
  * 💭 Why?
    * Originally this section was strict validation, but it became clear that we should allow newer-CLI-created config
      files that may have newer keys to work with older SDKs.
    * Similarly, it became clear that we're not validating environment variables this way, why config file keys?
    * We want the tools that mutate this file to have strong validation on the keys being added, so hopefully this
      avoids the concern of key typos.
* All keys are optional in the file. Ideally in the final merged form, we'd always require `address` and we always
  require `namespace` in namespace-specific clients (i.e. non cloud ops API), but it is unreasonable since we must fit
  within SDK defaults.
  * Originally this section did say `address` and `namespace` were required, but as SDK implementations came about, it
    became clear that can't be done easily, so CLI/SDK defaults need to remain.
* The default config file location is `<app-config-dir>/temporalio/temporal.json` for all platforms
  * This is as defined by https://pkg.go.dev/os#UserConfigDir which, as of this writing, is the logic defined in docs
    and in code at https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/os/file.go;l=528.
  * Existing CLI used `~/.config/temporalio/temporal.yaml`
    * ❓ Is this confusing for them? Are we concerned about them vs what is best moving forward?

### Environment variables

* Environment variables are in the form `TEMPORAL_<PROFILE_>_KEY_SUB_KEY_CAMEL_CASE`. If the profile part is missing,
default is assumed.
  * 💭 Why `TEMPORAL` prefix?
    * Reasonable to differentiate.
  * This means that `TEMPORAL_ADDRESS` and `TEMPORAL_DEFAULT_ADDRESS` are the same thing.
  * This means that camel case parts are separated by underscores _except_ the profile name itself.
    * So a config value of `profiles.myProfile.tls.clientCertPath` is `TEMPORAL_MYPROFILE_TLS_CLIENT_CERT_PATH`.
    * 💭 Why?
      * This is clearer for typing and it is unreasonable to try and break up user-supplied camel case.
  * Also the profile may contain an underscore and retain that and match that first. So
    `profiles.my_profile_tls.tls.clientCertPath` is `TEMPORAL_MY_PROFILE_TLS_TLS_CLIENT_CERT_PATH`.
    * 💭 Why?
      * It is unreasonable to elide any characters in the user-provided profile name.
    * ❓ Since these become parts of the env var, should we limit profile name characters overall? Maybe `A-Z`, `a-z`,
      `0-9`, and only `_-:/` for now. And do those last special characters become `_` in env vars? And therefore is it
      a failure to have two profile names that would result in the same env var?
* Environment variables are case-insensitive.
* The CLI has existing environment variables. Some of these work and some should be still supported but deprecated in
  favor of the new forms. Below are the CLI env vars and how they apply:
  * `TEMPORAL_ADDRESS` - works just fine.
  * `TEMPORAL_NAMESPACE` - works just fine.
  * `TEMPORAL_API_KEY` - works just fine.
  * `TEMPORAL_TLS` - works just fine.
  * `TEMPORAL_TLS_CERT`, `TEMPORAL_TLS_CERT_DATA`, and other mTLS client values - need to be deprecated and replaced
    with newer forms (only slight changes here).
    * 💭 Why not just have the `tls` config field be `certData` instead of `clientCertData` so this doesn't have to
      change?
      * Not being clear this is for mTLS client use is confusing to users. And we'd have to change the path one anyways
        because the CLI is not suffixed with path.
  * `TEMPORAL_TLS_X` for all other values - ones that don't match need to be deprecated and replaced with newer forms.
  * `TEMPORAL_CODEC_ENDPOINT` - works just fine.
  * `TEMPORAL_CODEC_AUTH` - works just fine.
  * 💭 Why deprecate some instead of making all our clients support these variables that exist in CLI?
    * It is more sane/reasonable to have a simple to understand config-field-to-env-var format than it is to have these
      special environment variables be inconsistent outliers.
    * For non-CLI uses (i.e. SDKs), it is unreasonable to burden them with past CLI choices.
* There are some special environment variables respected by clients:
  * `TEMPORAL_PROFILE` - the name of the profile to load if one is not provided at load time. The default is  `default`.
  * `TEMPORAL_CONFIG_FILE` - the path to the config file. The default is `~/.config/temporalio/temporal.json`.
* ❓ How to do grpc-meta as env var? Like for `My-Header: My-Value`
  * Env var names are case-insensitive and don't use dashes, so we can't put header name in env var name. And we may not
    want to canonicalize the header names even though most gRPC clients do it for you.
  * There's no obvious env var approach to array of strings, and it can't be completely comma-delimited because header
    values often contain commas. Would rather not force users to have an index in the env var name. Should we just not
    support gRPC meta from env var until we think this through?

### Loading Configuration

Configuration is loaded in the following manner:

* Try to load profile from configuration file
  * Only if file loading is enabled
  * Can If user provides specific config file, use that, otherwise use the default location
  * If user specifies the profile, use that, otherwise use the default
* Try to overwrite with specific configuration environment variables
  * Only if env loading is enabled
  * If user specifies the profile, use that, otherwise use the default
  * If the `default` profile is being loaded, try the profile-specific environment variable first, e.g.
    `TEMPORAL_DEFAULT_ADDRESS` is used over `TEMPORAL_ADDRESS` if it's present.
  * The `default` env vars are only for the default profile, meaning a profile of `foo` cannot use `TEMPORAL_ADDRESS`,
    only `TEMPORAL_FOO_ADDRESS` if present.

That is it, nothing more complicated. When the configuration is provided to the SDKs/CLI, they apply their normal logic
which includes defaults for things that can be defaulted, or errors if they expect something that is not provided (this
is SDK specific).

## Implementation

### CLI

* CLI will accept `--profile`.
  * This deprecates `--env`/`--env-file`
    * 💭 Why deprecate?
      * The `env` name is confusing with environment variables. Note we do not use the term "environment" anywhere in
        this document except for environment variables.
      * The `env` setting uses YAML files in `~/.config/temporalio/temporal.yaml`.
    * Error if both options are present, or in the case of default, if there are default files for both.
      * 💭 Why error in the case of both default env and profile being present instead of merge?
        * This is the new way and we should not try to support both at the same time, it can get confusing.
  * The default is `default`, and this can also be set via `TEMPORAL_PROFILE` env var.
* CLI will accept `--config-file`.
  * Default is `~/.config/temporalio/temporal.json`, also can be set via `TEMPORAL_CONFIG_FILE` env var.
* CLI will have a whole new set of `config` commands that operate similar to `env` commands today.
  * Will not go into detail in this proposal, but it's very similar.
  * We will strictly validate keys when setting whereas we did not with `env`.
* Unlike `env`/`--env`, this does not blindly apply any field as any CLI argument.
  * 💭 Why?
    * We want strict validation of config values. The idea that you can set a `workflow-id` as part of this profile does
      not make sense. These are client options only, declarative options for other things can be discussed separately.
* CLI should defer to the Go SDK for loading/using the config/profile.

### SDKs

SDKs must support loading client configuration from optional profile name and optional config name. This needs to
include a way to make sure that user-defaults can be set.

Possible language-specific ideas are below. Note, they are not exact and the naming is all subject to change, they are
simply ideas for discussion. Many of the approaches below are based on several rewritings after seeing how they don't
work in some SDKs. The overall approach is to just make client and connection options loadable from configuration
without overthinking shortcuts or merging or hierarchies.

#### Go SDK Idea

Some decisions here are explained here even though they apply to later SDKs. 

* New function in `client`: `LoadConfig(LoadConfigOptions) (*proto.Config, error)`.
  * This is mostly a helper if people want it.
* `LoadConfigOptions` has the following:
  * `ConfigFile string` - Override the file to use.
  * `DisableFile bool` - Disable reading from file.
  * `DisableEnv bool` - Disable reading from env vars.
* New function in `client`: `LoadOptionsFromConfig(string profile, LoadConfigOptions) (Options, error)`.
  * 💭 Why require profile, isn't there a default of `default`?
    * Yes, and maybe that's what empty string is too, but in general Go doesn't have good parameter defaults and we
      don't want a differently named overload just for this.
* New function in `client`: `NewOptionsFromConfig(*proto.ConfigProfile) (Options, error)`.
  * 💭 Why is this needed if `LoadOptionsFromConfig` exists?
    * People need a way to provide the config to load from instead of always assuming it can be loaded.
  * 💭 Why not have the config proto to use in the `LoadConfigOptions` instead?
    * It gets to be a bit of a merge game if you have a `BaseConfig` there, and it's a bit confusing if you have
      `PreloadedConfig` there which implies all other options don't matter.
* 💭 Why not just have the load config options on the client options and let dialing load?
  * People need to adjust options _after_ loaded (overwrite defaults, etc).
* 💭 Why not have `(*Options).LoadFromConfig` helper method on the options instead?
  * The merging logic gets far too complicated to know what to overwrite and what not to. It's better to force the user
    to start from config and handle merging themselves if they need that.
* Go SDK _does_ support codec settings because it supports remote codecs.
  * If the remote codec setting is set, the data converter option will be set.
  * 💭 Why not have a `PayloadCodecFromConfig` type of thing?
    * This is easy enough for users to do with the `LoadConfig` helper and the remote codec objects.
    * Most won't need it because regular `LoadOptionsFromConfig` creates it with default payload conversion. Only those
      that need customized payload conversion will need to create the remote codec themselves.
* Options like grpc-meta sets header provider, API key sets credentials, etc.
  * 💭 Why make a user that just wants to _add_ a header on top of config have to use `LoadConfig` and do it the hard
    way?
    * There's no clean way to support single header adding on top of existing ones in the Go SDK today.

Simplest example:

```go
options, err := client.LoadOptionsFromConfig("default")
if err != nil {
  return err
}
cl, err := client.Dial(options)
```

#### Java SDK Idea

* New static `ServiceStubsOptions.loadConfig()` and
  `ServiceStubsOptions.loadConfig(@Nullable String configFile, boolean disableFile, boolean disableEnv)` that return the
  full protobuf `Config` object.
  * ❓Any better place to put this? It's a proto utility, not a service stub utility.
* New static `WorkflowServiceStubsOptions.loadBuilderFromConfig()` and
  `WorkflowServiceStubsOptions.loadBuilderFromConfig(@Nullable String profile, @Nullable configFile, ` +
  `boolean disableFile, boolean disableEnv)` and
  `WorkflowServiceStubsOptions.newBuilderFromConfig(ConfigProfile profile)`.
  * 💭 Why not have these loaders as instance methods on the builder?
    * Same reason as Go, because the merging logic of knowing what to do with existing data is too complicated and it's
      best for the user to do that as needed.
* Need the same for operator and cloud service stubs options.
* Need same methods for `WorkflowClientOptions`.
  * Unfortunately with how Java works, there are separate client options, and they too can be in config.
  * ❓ Any alternative suggestions here? We could have some kind of shortcut to do multiple steps here.
* ❓ Does Java have a concept of a remote codec?

Simplest example:

```java
var stubsOptions = WorkflowServiceStubsOptions.loadBuilderFromConfig().build();
var stubs = WorkflowServiceStubs.newServiceStubs(stubsOptions);
var clientOptions = WorkflowClientOptions.loadBuilderFromConfig().build();
var client = WorkflowClient.newInstance(stubs, clientOptions);
```

#### TypeScript SDK Idea

* New `client` module function `loadConfig(options?)` where the `options` type is
  `{ configFile?: string, disableFile?: bool, disableEnv?: bool }` and it returns a `proto.Config`.
* New `client` module function `loadOptionsFromConfig(options?)` where the optional `options` are
  either `proto.ConfigProfile` or `{ profile?: string, configFile?: string, disableFile?: bool, disableEnv?: bool }` and
  it returns a `ConnectionOptions & ClientOptions`.
  * Could also have it return `{ connectionOptions: ConnectionOptions, clientOptions: ClientOptions }` if that makes
    more sense than a union.
* Consider a new async `Client.connect` static method that accepts `ConnectionOptions & ClientOptions` and is a
  shortcut to the two-step process today.
* TypeScript SDK _does not_ support codec settings and will error if seen in config.
  * 💭 Why error?
    * Because a user with a profile configured with a codec should expect that codec to be used, not silently ignored.

Simplest example:

```typescript
const options = loadOptionsFromConfig();
const connection = Connection.connect(options);
const client = new Client({ connection, ...options });

// Or maybe:

const { connectionOptions, clientOptions } = loadOptionsFromConfig();
const connection = Connection.connect(connectionOptions);
const client = new Client({ connection, ...clientOptions });
```

#### Python SDK Idea

* In `service` module, new function `load_config` with kwarg parameters of `config_file: Optional[str] = None`,
  `disable_file: bool = False`, `disable_env: bool = False` and it returns a `proto.Config`.
* In `service` module, new static method `ConnectConfig.load_from_config` with positional parameter of
  `profile: str = 'default'` and kwarg parameters of `config_file: Optional[str] = None`, `disable_file: bool = False`,
  and `disable_env: bool = False` and it returns a `ConnectConfig`.
* In `service` module, new static method `ConnectConfig.from_config` that accepts a single positional parameter of
  `proto.ConfigProfile`.
* In `client` module, new static methods for `ClientConfig.load_from_config` and `ClientConfig.from_config` same as
  above two for service module.
* In `client` module, new `TypedDict` class called `ClientConnectConfig` that extends `ClientConfig` but adds all the
  other parameters for `connect`.
  * On that class, new static methods for `load_from_config` and `from_config` that are like the others.
  * This config can mutated and splatted as the args to `Client.connect`.
    * 💭 Why not a separate `connect` call purely for config?
      * Many users want to set other options after config loads, and like with other SDKs adding config loading at the
        same time has option setting has many merge problems, so we need them to be separate steps.
* Like TypeScript, Python SDK _does not_ support codec settings and will error if seen in config.

Simplest example:

```python
config = ClientConnectConfig.load_from_config()
client = await Client.connect(**config)
```

#### .NET SDK Idea

* New static methods on `TemporalConnectionOptions` for `LoadConfig()` and
  `LoadConfig(string? configFile, bool disableFile, bool disableEnv)` and it returns `proto.Config`.
  * ❓Like Java, any better place to put this? It's a proto utility, not an options utility.
* New static methods on `TemporalConnectionOptions` for `LoadFromConfig()`,
  `LoadFromConfig(string profile = "default", string? configFile, bool disableFile, bool disableEnv)`.
  and `LoadFromConfig(proto.ConfigProfile)` that all return `TemporalConnectionOptions`.
* Same static methods on `TemporalClientConnectOptions`.
* Same static methods on `TemporalClientOptions`.
* Like TypeScript, .NET SDK _does not_ support codec settings and will error if seen in config.

Simplest example:

```csharp
var options = TemporalClientConnectOptions.LoadFromConfig();
var client = await TemporalClient.ConnectAsync(options);
```

### Samples

* All samples will be updated to load from config and default to local dev server w/ default namespace.
  * In samples we try to avoid shared code. In .NET and Python, there is no default target host, and in Ruby there will
    not even be a default namespace. So every sample in these languages is going to have to not only have the
    load-from-config code, but also conditionally apply the target host as `localhost:7233` if not set in external
    config.

### UI

* The UI could offer, say on API key creation, the ability to download a config file for use.
  * Since we require all profiles in a single file in the default place, the downloaded file would be just including the
    `default` profile and the instructions would tell them where to place it or they could provide this config file
    in any client at connection option time.