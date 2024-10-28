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
* Must be an "extension" to SDKs so the core SDK does not have dependencies added.
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
options, err := envconfig.LoadClientOptionsFromConfig("default")
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

Now running the same code again unmodified will run against cloud. You can do the same thing with config file in TOML:

```toml
[profile.default]
address = "my-ns.a1b2c.tmprl.cloud:7233"
namespace = "my-ns.a1b2c"
tls.client_cert_path = "path/to/my/client.pem"
tls.client_key_path = "path/to/my/client.pem"
```

And you can provide that config file or put it in the default place. You can also do this via CLI:

    temporal config set --key address --value my-ns.a1b2c.tmprl.cloud:7233
    temporal config set --key namespace --value my-ns.a1b2c
    temporal config set --key tls.client_cert_path --value path/to/my/cert.pem
    temporal config set --key tls.client_key_path --value path/to/my/cert.key

Or in a Temporal future with API keys you can use it instead.

#### Profile Switching

Similar to AWS tooling and other tools, you can have profiles. So you can have a config like:

```toml
[profile.dev]
address = "my-dev-ns.a1b2c.tmprl.cloud:7233"
namespace = "my-dev-ns.a1b2c"
tls.client_cert_path = "path/to/my/dev-cert.pem"
tls.client_key_path = "path/to/my/dev-cert.pem"

[profile.prod]
address = "my-prod-ns.a1b2c.tmprl.cloud:7233"
namespace = "my-prod-ns.a1b2c"
tls.client_cert_path = "path/to/my/prod-cert.pem"
tls.client_key_path = "path/to/my/prod-cert.pem"
```
Or in CLI, dev:

    temporal config set --profile dev --key address --value my-dev-ns.a1b2c.tmprl.cloud:7233
    temporal config set --profile dev --key namespace --value my-dev-ns.a1b2c
    temporal config set --profile dev --key tls.client_cert_path --value path/to/my/dev-cert.pem
    temporal config set --profile dev --key tls.client_key_path --value path/to/my/dev-cert.key

And prod:

    temporal config set --profile prod --key address --value my-prod-ns.a1b2c.tmprl.cloud:7233
    temporal config set --profile prod --key namespace --value my-prod-ns.a1b2c
    temporal config set --profile prod --key tls.client_cert_path --value path/to/my/prod-cert.pem
    temporal config set --profile prod --key tls.client_key_path --value path/to/my/prod-cert.key

Now a simple setting of `TEMPORAL_PROFILE` environment to `dev` or `prod` will switch connectivity (or `--profile` on
CLI or the string in the SDK if you don't want to use environment variable).

#### Possible UI Creation Flow

When a user creates an API key, the completion screen can provide a download of the config file that will have the
address, namespace, and API key set. So it can say something like:

```
API key is created, make sure you copy it here because it is not stored:

    <some long api key string>

Alternatively, you can download it as a configuration file:

    <some button or something that downloads a file name temporalio.toml>

You can place this configuration file in the default place used by CLIs/SDKs:

* macOS - `$HOME/Library/Application Support/temporalio/temporal.toml`
* Windows - `%AppData%/temporalio/temporal.toml` (often `C:\Users\<myuser>\AppData\Roaming\temporalio\temporal.toml`)
* Linux - `$HOME/.config/temporalio/temporal.toml`

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

#### Multi-Namespace Config Use

Some users may want the same configuration for multiple namespaces (or multiple addresses or multiple API keys or
whatever). Users can supply partial configuration. For instance, you can have this config:

```toml
[profile.default]
address = "my-dev-ns.a1b2c.tmprl.cloud:7233"
tls.client_cert_path = "path/to/my/dev-cert.pem"
tls.client_key_path = "path/to/my/dev-cert.pem"
```

And then still use CLI like

    temporal workflow list --namespace my-specific-namespace

This will use the config file information for all but the namespace. Similarly you could just set the
`TEMPORAL_NAMESPACE` env var to `my-specific-namespace` and run:

    temporal workflow list

Similarly, if you're using an SDK, you can load the config and just switch namespaces in code. So you can have:

```python
config = envconfig.load_client_connect_config()
client = await Client.connect(namespace="my-specific-namespace", **config)
```

## Specification

### Values and File Format

* The format is a TOML object with the following fields:
  * `profile` - Object with keys as profile names. The default profile should be named `default`.
    * `<name>` - Profile object with configuration values. Profile names are case-insensitive. 💭 Why? They are needed
      for environment variables which are case insensitive. It is a validation error to have a config file with two
      separately-cased profile names that are equal case-insensitively.
      * `address` - Client address, aka gRPC "host:port". This cannot be a URL, it must be `host:port`.
      * `namespace` - Client namespace.
      * `api_key` - Client API key.
      * `tls` - A boolean (true is same as empty object) _or_ an object. Note the default for this value is dependent
        upon other settings here. 💭 Why? We regret not making TLS the default in the past, so we will make it default
        if `api_key` is present. If TLS is an object, it can have the following possible fields:
        * `client_cert_path` - File path to mTLS client cert. Mutually exclusive with `client_cert_data`.
        * `client_cert_data` - Cert data. Mutually exclusive with `client_cert_path`.
        * `client_key_path` - File path to mTLS client key. Mutually exclusive with `client_key_data`.
        * `client_key_data` - Key data. Mutually exclusive with `client_key_path`.
        * `server_ca_cert_path` - File path to server CA cert. Mutually exclusive with `server_ca_cert_data`.
        * `server_ca_cert_data` - CA cert data. Mutually exclusive with `server_ca_cert_path`.
        * `server_name` - Override SNI name when connecting to server.
        * `disable_host_verification` - Boolean to disable verifying TLS server host. May not be available in all
          Temporal clients. 💭 Why? Not all SDKs offer this feature today.
      * `codec` - Remote codec information to use for all encoding/decoding of payloads. May not be available in all
        Temporal clients. 💭 Why? Not all SDKs allow use of a remote codec today.
        * `endpoint` - Endpoint to the remote codec.
        * `auth` - Authorization header for the remote codec.
      * `grpc_meta` - Object representing HTTP headers. Values must be strings for now (can discuss arrays later).
        ❓ Should we call this `headers`? We do in some cases and not others.
  * 💭 Why TOML?
    * Original document was JSON, but team discussion decided that the benefit to humans of TOML outweighed the concerns
      of making SDKs have extensions with TOML support.
* For settings that accept files above, they are relative to the current working directory.
  * 💭 Why not relative to the config file directory?
    * Because we also accept these config values as environment variables or programmatically, and it is confusing to
      have different rules for the same key in different ways. We want the environment variable to literally override
      the config file value, not also change the behavior.
* Each language will have its own models for this under an `envconfig`/`EnvConfig` namespace/package/module/extension
  * 💭 Why not define model in proto?
    * When JSON was the preferred format proto JSON made sense, but now that it is not, using proto only for SDK team's
      benefit of shared contract is not the easiest for users. So each language will have language-idiomatic models.
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
* The default config file location is `<app-config-dir>/temporalio/temporal.toml` for all platforms.
  * This is as defined by https://pkg.go.dev/os#UserConfigDir which, as of this writing, is the logic defined in docs
    and in code at https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/os/file.go;l=528.
  * Existing CLI used `~/.config/temporalio/temporal.yaml`
    * ❓ Is this confusing for them? Are we concerned about them vs what is best moving forward?
  * 💭 Why `temporal.toml` instead of `temporal-client.toml`?
    * After discussion, it was decided future non-client use of this config (which may never occur) can be sub keys of
      this file instead of having a separate file or separate config for every separate use. And client is the common
      enough initial (and maybe only) use case to get the top-level without burdening users.

### Environment variables

* Environment variables are in the form `TEMPORAL_KEY_SUB_KEY_CAMEL_CASE`. Profiles do not apply to environment
  variables. Environment variables always overwrite config if set regardless of config profile in use.
  * 💭 Why `TEMPORAL` prefix?
    * Reasonable to differentiate.
  * So for example, the `address` key is `TEMPORAL_ADDRESS`, etc.
  * This means that dot parts are separated by underscores.
    * So a config value of `tls.client_cert_path` is `TEMPORAL_TLS_CLIENT_CERT_PATH`.
    * 💭 Why?
      * This is clearer for users.
* Case-sensitivity is a platform specific thing, but Temporal uses all-caps.
* The CLI has existing environment variables. Some of these work and some should be still supported but deprecated in
  favor of the new forms. Below are the CLI env vars and how they apply:
  * `TEMPORAL_ADDRESS` - works just fine.
  * `TEMPORAL_NAMESPACE` - works just fine.
  * `TEMPORAL_API_KEY` - works just fine.
  * `TEMPORAL_TLS` - works just fine.
  * `TEMPORAL_TLS_CERT`, `TEMPORAL_TLS_CERT_DATA`, and other mTLS client values - need to be deprecated and replaced
    with newer forms (only slight changes here).
    * 💭 Why not just have the `tls` config field be `cert_data` instead of `client_cert_data` so this doesn't have to
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
* For gRPC metadata (i.e. HTTP headers), the environment variable format is `TEMPORAL_GRPC_META_<name>`.
  * `<name>` is canonicalized into HTTP header format (gRPC libraries do this for you).
  * Like all HTTP headers, comma-delimited values are supported for multi-headers.
  * This does require that environment variable lists be scanned for prefixes. This is deemed an acceptable tradeoff.
  * 💭 Why not `TEMPORAL_GRPC_META` as a single var that accepts some kind of structured format?
    * There isn't really a good structured format. Comma-delimited key=value would require users to escape commas in the
      value (common in HTTP values), there's not a good delimiter for other-delimited key=value, and requiring a JSON
      object as the env var value is a bit hard to use.
  * 💭 Why not `TEMPORAL_GRPC_META_<index>` as `key: value`?
    * Scanning has to happen anyways.
    * `TEMPORAL_GRPC_META_AUTHORIZATION` as `Bearer my-token` is cleaner than `TEMPORAL_GRPC_META_0` as
      `Authorization: Bearer my-token`.
    * Users shouldn't have to keep up with indexes.
  * 💭 Why not `TEMPORAL_GRPC_META` as a multiline set of headers?
    * This can be added later if wanted.
    * People want to be able to set individual headers.
    * If we use traditional header format, requires HTTP header parsing which is not as trivial as it may seem (and
      parsers may not be present/accessible in every standard library). Granted we could accept our own multiline format
      or only support a simple subset of the header format.
* There are some special environment variables respected by clients:
  * `TEMPORAL_PROFILE` - the name of the profile to load if one is not provided at load time. The default is  `default`.
  * `TEMPORAL_CONFIG_FILE` - the path to the config file. The default is `~/.config/temporalio/temporal-client.toml`.

### Loading Configuration

Configuration is loaded in the following manner:

* Try to load profile from configuration file
  * Only if file loading is enabled (which it is by default)
  * If user provides specific config file, use that, otherwise use the default location
  * If user specifies the profile, use that, otherwise use the default
* Try to overwrite with specific configuration environment variables
  * Only if env loading is enabled (which it is by default)

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
  * Default is `~/.config/temporalio/temporal.toml`, also can be set via `TEMPORAL_CONFIG_FILE` env var.
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

* New separately-versioned module at `go.temporal.io/sdk/contrib/envconfig`.
  * 💭 Why not just in the SDK?
    * We have to take a TOML dependency which is not fair to put on users that don't need this functionality.
* `ClientConfig` model (and sub-models like `ClientConfigTLS`) are the typed form of the config.
  * 💭 Why `ClientConfig` instead of `Config`?
    * We may have another form of config in the future. And if we get there and need an overarching `Config` to hold the
      separate ones we can have it.
* Function `LoadClientConfig(LoadClientConfigOptions) (ClientConfig, error)`.
  * This is an advanced helper, most would use `LoadClientOptionsFromConfig` below.
* `LoadClientConfigOptions` has the following:
  * `ConfigFile string` - Override the file to use.
  * `DisableFile bool` - Disable reading from file.
  * `DisableEnv bool` - Disable reading from env vars.
* Function `LoadClientOptionsFromConfig(string profile, LoadClientConfigOptions) (client.Options, error)`
  * Create Go SDK client options from config.
  * 💭 Why require profile, isn't there a default of `default`?
    * Yes, and maybe that's what empty string is too, but in general Go doesn't have good parameter defaults and we
      don't want a differently named overload just for this.
* Function `NewClientOptionsFromConfig(ClientConfig) (client.Options, error)`
  * 💭 Why is this needed if `LoadClientOptionsFromConfig` exists?
    * People need a way to provide the config to load from instead of always assuming it can be loaded.
  * 💭 Why not have the config struct to use in the `LoadClientConfigOptions` instead?
    * It gets to be a bit of a merge game if you have a `BaseConfig` there, and it's a bit confusing if you have
      `PreloadedConfig` there which implies all other options don't matter.
* 💭 Why not just have the load config options on the client options and let dialing load?
  * People need to adjust options _after_ loaded (overwrite defaults, etc).
* 💭 Why not have `(*ClientConfig).LoadFromConfig` helper method on the options instead?
  * The merging logic gets far too complicated to know what to overwrite and what not to. It's better to force the user
    to start from config and handle merging themselves if they need that.
* Go SDK _does_ support codec settings because it supports remote codecs.
  * If the remote codec setting is set, the data converter option will be set.
  * 💭 Why not have a `PayloadCodecFromConfig` type of thing?
    * This is easy enough for users to do with the `LoadClientOptionsFromConfig` helper and the remote codec objects.
    * Most won't need it because regular `LoadClientOptionsFromConfig` creates it with default payload conversion. Only
      those that need customized payload conversion will need to create the remote codec themselves.
* Options like grpc-meta sets header provider, API key sets credentials, etc.
  * 💭 Why make a user that just wants to _add_ a header on top of config have to use `LoadConfig` and do it the hard
    way?
    * There's no clean way to support single header adding on top of existing ones in the Go SDK today.

Simplest example:

```go
options, err := envconfig.LoadClientOptionsFromConfig("default", LoadClientConfigOptions{})
if err != nil {
  return err
}
cl, err := client.Dial(options)
```

#### Java SDK Idea

* New JAR project `temporal-envconfig` with package at `io.temporal.envconfig`.
  * 💭 Why not just in the SDK?
    * We have to take a TOML dependency which is not fair to put on users that don't need this functionality.
* New models for `ClientConfig` (and other things as needed).
* New static `ClientConfig.load()` and
  `ClientConfig.load(@Nullable String configFile, boolean disableFile, boolean disableEnv)` that return `ClientConfig`.
  * ❓Any better place to put this? It's a config utility, not a service stub utility.
* New instance `ClientConfig#toWorkflowServiceStubsOptions()` and static helpers like
  `ClientConfig.loadWorkflowServiceStubsOptions()` and the overload like `load` has.
* Need the same for operator and cloud service stubs options.
* Need same methods for `WorkflowClientOptions`.
  * Unfortunately with how Java works, there are separate client options, and they too can be in config.
  * ❓ Any alternative suggestions here? We could have some kind of shortcut to do multiple steps here.
* ❓ Does Java have a concept of a remote codec?

Simplest example:

```java
var stubsOptions = ClientConfig.loadWorkflowServiceStubsOptions();
var stubs = WorkflowServiceStubs.newServiceStubs(stubsOptions);
var clientOptions = ClientConfig.loadWorkflowClientOptions();
var client = WorkflowClient.newInstance(stubs, clientOptions);
```

#### TypeScript SDK Idea

* New package and module for `envconfig`.
  * 💭 Why not just in the SDK?
    * We have to take a TOML dependency which is not fair to put on users that don't need this functionality.
  * ❓ What about "native connection"?
    * Python and .NET and Ruby will use Rust Core to load this, so TypeScript may have to have two forms too, up to
      implementer.
* Needs `ClientConfig` interface (and other interfaces as needed).
* Needs `loadClientConfig(options?)` where the `options` type is
  `{ configFile?: string, disableFile?: bool, disableEnv?: bool }` and it returns a `ClientConfig`.
* Needs `loadClientOptionsFromConfig(options?)` where the optional `options` are
  either `ClientConfig` or `{ profile?: string, configFile?: string, disableFile?: bool, disableEnv?: bool }` and
  it returns a `ConnectionOptions & ClientOptions`.
  * Could also have it return `{ connectionOptions: ConnectionOptions, clientOptions: ClientOptions }` if that makes
    more sense than a union.
* TypeScript SDK _does not_ support codec settings and will error if seen in config.
  * 💭 Why error?
    * Because a user with a profile configured with a codec should expect that codec to be used, not silently ignored.

Simplest example:

```typescript
const options = loadClientOptionsFromConfig();
const connection = Connection.connect(options);
const client = new Client({ connection, ...options });

// Or maybe:

const { connectionOptions, clientOptions } = loadClientOptionsFromConfig();
const connection = Connection.connect(connectionOptions);
const client = new Client({ connection, ...clientOptions });
```

#### Python SDK Idea

* `temporalio.envconfig` module that uses Rust Core.
  * 💭 Why not pure Python TOML? At this time it was decided that the loading of the config is involved enough that we
    can use the Rust core (and not have a dependency). We acknowledge that pure in-language TOML could have value for
    saving at some later date, but this is good for now.
  * 💭 Why a separate module? Every other SDK is doing it.
  * ❓ Would we rather `temporalio.runtime.envconfig`? Other non-Core SDKs are just putting top-level.
* New `ClientConfig` dataclass (and others as needed).
* Static method `ClientConfig.load` with kwarg parameters of `config_file: Optional[str] = None`,
  `disable_file: bool = False`, `disable_env: bool = False` and it returns a `ClientConfig`.
* New `TypedDict` in `client` for `ConnectConfig` that matches all params in `connect`.
* Static method `ClientConfig.load_client_connect_config` with positional parameter of
  `profile: str = 'default'` and kwarg parameters of `config_file: Optional[str] = None`, `disable_file: bool = False`,
  and `disable_env: bool = False` and it returns a `client.ConnectConfig`
  * 💭 Why not call it `load_client_config`?
    * Because this class is a connect config and that is confusing.
* Instance method `to_client_connect_config` on the `ClientConfig`.
* Like TypeScript, Python SDK _does not_ support codec settings and will error if seen in config.

Simplest example:

```python
config = envconfig.ClientConfig.load_client_connect_config()
client = await Client.connect(**config)
```

#### .NET SDK Idea

* `Temporalio.EnvConfig` namespace that uses Rust Core.
  * 💭 Why not pure .NET TOML? At this time it was decided that the loading of the config is involved enough that we
    can use the Rust core (and not have a dependency). We acknowledge that pure in-language TOML could have value for
    saving at some later date, but this is good for now.
  * 💭 Why a separate namespace? Every other SDK is doing it.
  * ❓ Would we rather `Temporalio.Runtime.Envconfig` namespace? Other non-Core SDKs are just putting top-level.
* New `ClientConfig` record (and others as needed).
* Static method `ClientConfig.Load(string? configFile = null, bool disableFile = false, bool disableEnv = false)` that
  returns `ClientConfig`.
* Static method `ClientConfig.LoadClientConnectOptions` with same params.
* Instance method on `ClientConfig` for `ToClientConnectOptions`.
* Like TypeScript, .NET SDK _does not_ support codec settings and will error if seen in config.

Simplest example:

```csharp
var options = ClientConfig.LoadClientConnectOptions();
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