# Proposal: ToolRegistry + AgenticSession — Cross-SDK LLM Tool-Calling Primitives

**SDKs:** Python · TypeScript · Go · Java · Ruby · .NET

---

## Problem

LLM-backed activities are increasingly common in Temporal workflows, but every team wires up the tool-calling loop themselves. The result is repeated, fragile boilerplate:

- Serialize tool definitions to Anthropic/OpenAI schema format
- Dispatch `tool_use` / `function` blocks back to local handlers
- Accumulate conversation history and iterate until the model stops
- Heartbeat the conversation state so an activity retry can resume mid-session rather than restart

There is no shared abstraction — not across teams, and not across SDKs. This proposal defines two complementary primitives and ships them as contributed modules in all six official Temporal SDKs.

---

## Overview

Two abstractions cover the common cases:

**`ToolRegistry`** — maps tool names to JSON Schema definitions and handler functions, exports to Anthropic or OpenAI wire format, and dispatches model-selected tool calls.

**`AgenticSession`** — wraps a `ToolRegistry` loop with crash-safe heartbeating. Before every LLM turn it serializes the conversation history and issues list via `heartbeat`; on retry the activity resumes from where it left off.

Both are opt-in `contrib` modules (not part of the SDK core) and have no mandatory dependencies — LLM client libraries are `require`/`import`-ed at runtime only if a real provider is constructed.

---

## Design decisions

### Tool definitions use JSON Schema inline

Each tool is described with a plain dictionary/map matching Anthropic's `tool_use` format (`name`, `description`, `input_schema`). This is also the schema required by the MCP protocol, making registry objects reusable with MCP tool descriptors.

OpenAI format is derived from the same definitions via `toOpenAI()` / `to_openai()`, which wraps each definition in the `{"type": "function", "function": {...}}` envelope OpenAI requires.

### Provider strategy: string vs. object

**Python and TypeScript** take `provider: str` (`"anthropic"` or `"openai"`) in `run_tool_loop`. The string is simpler to write in the common case and reduces the number of types a caller must import. The `AgenticSession.run_tool_loop` method also takes the string.

**Go, Java, Ruby, and .NET** use an explicit `Provider` object (interface in Java/Go/.NET, base class in Ruby). This makes testing cleaner — passing a `MockProvider` requires no magic — and exposes the seam used by `AgenticSession` to call into the model.

This difference is deliberate, not an oversight. Both approaches are idiomatic for their ecosystems.

### Ruby naming: `Registry` inside the `ToolRegistry` module

In Ruby the class is `Temporalio::Contrib::ToolRegistry::Registry`, not `ToolRegistry::ToolRegistry`. Repeating the outermost module name in the class name is un-idiomatic Ruby (same pattern used throughout the other Ruby contrib packages). Callers can alias freely:

```ruby
Registry = Temporalio::Contrib::ToolRegistry::Registry
```

### Session entry point style

Each SDK uses the idiomatic entry point for asynchronous callbacks:

| SDK | Entry point |
|-----|------------|
| Python | `async with agentic_session() as session:` |
| TypeScript | `await agenticSession(async (session) => { ... })` |
| Go | `toolregistry.RunWithSession(ctx, func(ctx, s) error { ... })` |
| Java | `AgenticSession.runWithSession(session -> { ... })` |
| Ruby | `AgenticSession.run_with_session { \|session\| ... }` |
| .NET | `await AgenticSession.RunWithSessionAsync(async session => { ... })` |

All are equivalent in behavior; the style difference is purely idiomatic.

### Heartbeat timing

The checkpoint is written **before** each LLM turn (not after). This guarantees that if the activity is killed mid-turn — e.g., while waiting on the network — the next retry will re-issue the same turn rather than advance past it. It is safe to repeat a turn: the conversation history already includes the user message, so the model will produce the same (or equivalent) response.

### Cancellation

All SDKs surface cancellation at the checkpoint call, immediately after writing the heartbeat. The mechanisms differ per-language idiom (Go: `ctx.Err()`, Java: `ActivityCompletionException`, Ruby: `CanceledError`, .NET: `CancellationToken`, Python/TS: implicit via context propagation) but the semantics are identical.

---

## API reference

### Python

```python
from temporalio.contrib.tool_registry import (
    ToolRegistry, run_tool_loop, agentic_session, AgenticSession,
)

# Simple loop
tools = ToolRegistry()

@tools.handler({
    "name": "flag_issue",
    "description": "Flag a problem found in the analysis",
    "input_schema": {
        "type": "object",
        "properties": {"description": {"type": "string"}},
        "required": ["description"],
    },
})
def handle_flag(inp: dict) -> str:
    issues.append(inp["description"])
    return "recorded"

await run_tool_loop(
    provider="anthropic",          # or "openai"
    system="You are a code reviewer. Call flag_issue for each problem you find.",
    prompt=prompt,
    tools=tools,
)

# Crash-safe session
async with agentic_session() as session:
    tools = ToolRegistry()

    @tools.handler({...})
    def handle(inp):
        session.issues.append(inp)
        return "ok"

    await session.run_tool_loop(
        registry=tools, provider="anthropic",
        system="...", prompt=prompt,
    )
return session.issues
```

Module: `temporalio/contrib/tool_registry/`
Test: `tests/contrib/tool_registry/`

---

### TypeScript

```typescript
import { ToolRegistry, runToolLoop, agenticSession } from '@temporalio/tool-registry';

// Simple loop
const registry = new ToolRegistry();
registry.define(
  {
    name: 'flag_issue',
    description: 'Flag a problem found in the analysis',
    input_schema: {
      type: 'object',
      properties: { description: { type: 'string' } },
      required: ['description'],
    },
  },
  (inp) => { issues.push(inp['description'] as string); return 'recorded'; }
);

await runToolLoop({
  provider: 'anthropic',   // or 'openai'
  system: 'You are a code reviewer. Call flag_issue for each problem you find.',
  prompt,
  tools: registry,
});

// Crash-safe session
const issues = await agenticSession(async (session) => {
  const registry = new ToolRegistry();
  registry.define({...}, (inp) => {
    session.issues.push(inp);
    return 'ok';
  });
  await session.runToolLoop({ registry, provider: 'anthropic', system: '...', prompt });
  return session.issues;
});
```

Package: `packages/tool-registry/`
Tests: `packages/tool-registry/src/*.test.ts`

---

### Go

```go
import "go.temporal.io/sdk/contrib/toolregistry"

// Simple loop
reg := toolregistry.NewToolRegistry()
reg.Register(toolregistry.ToolDef{
    Name:        "flag_issue",
    Description: "Flag a problem found in the analysis",
    InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{"description": map[string]any{"type": "string"}},
        "required":   []string{"description"},
    },
}, func(inp map[string]any) (string, error) {
    issues = append(issues, inp["description"].(string))
    return "recorded", nil
})

cfg := toolregistry.AnthropicConfig{APIKey: os.Getenv("ANTHROPIC_API_KEY")}
provider := toolregistry.NewAnthropicProvider(cfg, reg,
    "You are a code reviewer. Call flag_issue for each problem you find.")

if _, err := toolregistry.RunToolLoop(ctx, provider, reg, "", prompt); err != nil {
    return nil, err
}

// Crash-safe session
err := toolregistry.RunWithSession(ctx, func(ctx context.Context, s *toolregistry.AgenticSession) error {
    reg := toolregistry.NewToolRegistry()
    reg.Register(toolregistry.ToolDef{...}, func(inp map[string]any) (string, error) {
        s.Issues = append(s.Issues, inp)
        return "ok", nil
    })
    provider := toolregistry.NewAnthropicProvider(cfg, reg, "...")
    return s.RunToolLoop(ctx, provider, reg, "...", prompt)
})
```

Package: `contrib/toolregistry/`
Tests: `contrib/toolregistry/*_test.go`

---

### Java

```java
import io.temporal.toolregistry.*;

// Simple loop
ToolRegistry registry = new ToolRegistry();
registry.register(
    ToolDefinition.builder()
        .name("flag_issue")
        .description("Flag a problem found in the analysis")
        .inputSchema(Map.of(
            "type", "object",
            "properties", Map.of("description", Map.of("type", "string")),
            "required", List.of("description")))
        .build(),
    input -> {
        issues.add((String) input.get("description"));
        return "recorded";
    });

Provider provider = new AnthropicProvider(
    AnthropicConfig.builder().apiKey(System.getenv("ANTHROPIC_API_KEY")).build(),
    registry,
    "You are a code reviewer. Call flag_issue for each problem you find.");

ToolRegistry.runToolLoop(provider, registry, "", prompt);

// Crash-safe session
AgenticSession.runWithSession(session -> {
    ToolRegistry registry = new ToolRegistry();
    registry.register(ToolDefinition.builder()...build(), input -> {
        session.getIssues().add(input);
        return "ok";
    });
    session.runToolLoop(provider, registry, "...", prompt);
});
```

Module: `temporal-tool-registry/`
Tests: `temporal-tool-registry/src/test/`

---

### Ruby

```ruby
require 'temporalio/contrib/tool_registry'
require 'temporalio/contrib/tool_registry/providers/anthropic'

# Simple loop
registry = Temporalio::Contrib::ToolRegistry::Registry.new
registry.register(
  name: 'flag_issue',
  description: 'Flag a problem found in the analysis',
  input_schema: {
    'type' => 'object',
    'properties' => { 'description' => { 'type' => 'string' } },
    'required' => ['description']
  }
) do |input|
  issues << input['description']
  'recorded'
end

provider = Temporalio::Contrib::ToolRegistry::Providers::AnthropicProvider.new(
  registry,
  'You are a code reviewer. Call flag_issue for each problem you find.',
  api_key: ENV['ANTHROPIC_API_KEY']
)
Temporalio::Contrib::ToolRegistry.run_tool_loop(provider, registry, nil, prompt)

# Crash-safe session
Temporalio::Contrib::ToolRegistry::AgenticSession.run_with_session do |session|
  registry = Temporalio::Contrib::ToolRegistry::Registry.new
  registry.register(name: 'flag', description: '...',
                    input_schema: { 'type' => 'object' }) do |input|
    session.issues << input
    'ok'
  end
  session.run_tool_loop(provider, registry, '...', prompt)
end
```

Path: `temporalio/lib/temporalio/contrib/tool_registry/`
Tests: `temporalio/test/contrib/tool_registry_test.rb`

---

### .NET

```csharp
using Temporalio.Extensions.ToolRegistry;
using Temporalio.Extensions.ToolRegistry.Providers;

// Simple loop
var registry = new ToolRegistry();
registry.Register(
    new ToolDefinition(
        Name: "flag_issue",
        Description: "Flag a problem found in the analysis",
        InputSchema: new Dictionary<string, object>
        {
            ["type"] = "object",
            ["properties"] = new Dictionary<string, object>
                { ["description"] = new Dictionary<string, object> { ["type"] = "string" } },
            ["required"] = new[] { "description" },
        }),
    inp =>
    {
        issues.Add((string)inp["description"]);
        return Task.FromResult("recorded");
    });

var provider = new AnthropicProvider(
    new AnthropicConfig { ApiKey = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY") },
    registry,
    "You are a code reviewer. Call flag_issue for each problem you find.");

await ToolRegistry.RunToolLoopAsync(provider, registry, "", prompt);

// Crash-safe session
var result = await AgenticSession.RunWithSessionAsync(async session =>
{
    var registry = new ToolRegistry();
    registry.Register(new ToolDefinition(...), inp =>
    {
        session.Issues.Add(inp);
        return Task.FromResult("ok");
    });
    await session.RunToolLoopAsync(provider, registry, "...", prompt);
    return session.Issues;
});
```

Project: `src/Temporalio.Extensions.ToolRegistry/`
Tests: `tests/Temporalio.Extensions.ToolRegistry.Tests/`

---

## Testing without an API key

All SDKs ship a `MockProvider` that replays a scripted sequence of responses. This keeps unit tests fast, hermetic, and free of credentials.

### Python

```python
from temporalio.contrib.tool_registry.testing import MockProvider, MockResponse

provider = MockProvider([
    MockResponse.tool_call("flag_issue", {"description": "stale API"}),
    MockResponse.done("analysis complete"),
])
msgs = await run_tool_loop(provider=provider, system="sys", prompt="analyze", tools=tools)
assert len(msgs) > 2
```

### TypeScript

```typescript
import { MockProvider, MockResponse } from '@temporalio/tool-registry/testing';

const provider = new MockProvider([
  MockResponse.toolCall('flag_issue', { description: 'stale API' }),
  MockResponse.done('analysis complete'),
]);
const msgs = await runToolLoop({ provider, system: 'sys', prompt: 'analyze', tools: registry });
assert.ok(msgs.length > 2);
```

### Go

```go
provider := toolregistry.NewMockProvider([]toolregistry.MockResponse{
    toolregistry.ToolCall("flag_issue", map[string]any{"description": "stale API"}),
    toolregistry.Done("analysis complete"),
}).WithRegistry(reg)

msgs, err := toolregistry.RunToolLoop(ctx, provider, reg, "sys", "analyze")
require.NoError(t, err)
require.Greater(t, len(msgs), 2)
```

### Java

```java
MockProvider provider = new MockProvider(
    MockResponse.toolCall("flag_issue", Map.of("description", "stale API")),
    MockResponse.done("analysis complete"));

List<Map<String, Object>> msgs =
    ToolRegistry.runToolLoop(provider, registry, "sys", "analyze");
assertTrue(msgs.size() > 2);
```

### Ruby

```ruby
provider = Testing::MockProvider.new(
  Testing::MockResponse.tool_call('flag_issue', { 'description' => 'stale API' }),
  Testing::MockResponse.done('analysis complete')
).with_registry(registry)

msgs = ToolRegistry.run_tool_loop(provider, registry, 'sys', 'analyze')
assert msgs.length > 2
```

### .NET

```csharp
var provider = new MockProvider(
    MockResponse.ToolCall("flag_issue", new Dictionary<string, object> { ["description"] = "stale API" }),
    MockResponse.Done("analysis complete")
).WithRegistry(registry);

var msgs = await ToolRegistry.RunToolLoopAsync(provider, registry, "sys", "analyze");
Assert.True(msgs.Count > 2);
```

---

## Real-provider integration tests

Each SDK includes Anthropic and OpenAI integration tests gated on `RUN_INTEGRATION_TESTS`. Tests are skipped automatically when the env var is absent. To run:

```bash
export RUN_INTEGRATION_TESTS=1
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...

# Python
cd sdk-python && pytest tests/contrib/tool_registry/ -k integration -v

# TypeScript
cd sdk-typescript && npx mocha --require ts-node/register \
  'packages/tool-registry/src/**/*.test.ts' --grep integration

# Go
cd sdk-go && go test -v -run TestIntegration ./contrib/toolregistry/

# Java
cd sdk-java && JAVA_HOME=$JDK21 ./gradlew :temporal-tool-registry:test \
  --tests "*.testIntegration_*" --no-daemon

# Ruby
cd sdk-ruby/temporalio && bundle exec rake test

# .NET
cd sdk-dotnet && dotnet test tests/Temporalio.Extensions.ToolRegistry.Tests/
```

---

## Scope and non-goals

**In scope:**
- `ToolRegistry` — tool definition storage, format export, handler dispatch
- `AnthropicProvider` / `OpenAIProvider` — multi-turn loops for each provider
- `AgenticSession` — crash-safe heartbeat wrapper
- `MockProvider` — scripted test double for unit tests
- `ToolRegistryPlugin` — Temporal worker sandbox configuration (Python/TypeScript)
- MCP tool import (`from_mcp_tools` / `fromMcpTools`) — converts MCP descriptors to native definitions

**Out of scope:**
- Streaming responses
- Structured output (non-tool response parsing)
- Automatic retry / back-pressure on rate limits
- Multi-agent orchestration
- Prompt management / template libraries

---

## Open questions

1. **Package naming**: Should this ship as `contrib/toolregistry` (current) or a top-level extension package? The `.NET` version already uses the `Temporalio.Extensions.*` namespace.

2. ~~**MCP coverage**: `from_mcp_tools` exists in Python and TypeScript. Should it be added to Go, Java, Ruby, .NET?~~ **Resolved**: `fromMcpTools` / `from_mcp_tools` / `FromMCPTools` added to Go, Java, Ruby, and .NET. All six SDKs now have MCP support.

3. **Versioning**: These modules are in `contrib` and thus can evolve independently. Should they carry a `v0` semver disclaimer for the first release?

---

## PRs

| SDK | PR |
|-----|----|
| Go | temporalio/sdk-go#2292 |
| Python | temporalio/sdk-python#1435 |
| TypeScript | temporalio/sdk-typescript#2008 |
| Java | temporalio/sdk-java#2839 |
| Ruby | temporalio/sdk-ruby#417 |
| .NET | temporalio/sdk-dotnet#641 |

## Related issues

- temporalio/sdk-python#1089
- temporalio/sdk-typescript#1755
