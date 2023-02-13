# Typed Search Attributes in SDKs

Today most languages just do arbitrary lists for search attribute values or half-implementations of some-list some not.
This is a problem now with the server having multiple different forms of search attributes and preferring non-lists.
Below is just a proposal of ideas on how better to type search attributes.

## Current behavior

### SDK

* Go
  * Search attributes getting in workflow - on info as raw proto `*commonpb.SearchAttributes`
  * Search attributes setting in workflow - via `UpsertSearchAttributes` accepting `map[string]interface{}`
  * Search attributes setting on start - via `map[string]interface{}` on start options
  * Search attributes getting on list/describe - not available in high-level
* Java
  * Search attributes getting in workflow - via `getSearchAttributes` for all as `Map<String, List<?>>`
  * Search attribute getting in workflow - via `getSearchAttribute` for single values and `getSearchAttributeValues` for
    multi values (but works for single)
  * Search attributes setting in workflow - via `upsertSearchAttributes` accepting `Map<String, ?>`
  * Search attributes setting on start - via `Map<java.lang.String,​ ?>` on start options
  * Search attributes getting on list/describe - as `Map<java.lang.String,​ ?>` on list but no high-level describe form
    (from latest javadoc, though didn't check repo where we may have new describe form)
* TS
  * Search attributes getting in workflow - on info as `Record<string, scalar[]>` (i.e. object)
  * Search attributes setting in workflow - via `upsertSearchAttributes` accepting `Record<string, scalar[]>`
  * Search attributes setting on start - via `Record<string, scalar[]>` on start options
  * Search attributes getting on list/describe - as `Record<string, scalar[]>`
* Python
  * Search attributes getting in workflow - on info as `Mapping[str, List[scalar]]`
  * Search attributes setting in workflow - via `upsert_search_attributes` accepting `Mapping[str, List[scalar]]`
  * Search attributes setting on start - via `Mapping[str, List[scalar]]` on start options
  * Search attributes getting on list/describe - as `Mapping[str, List[scalar]]`
* .NET
  * Still in alpha, can decide whatever we want

### Server

* ElasticSearch
  * Multi-value search attribute for non-keyword-list - accepted, but discouraged, and returned as given
    * TODO(cretz): Question outstanding to server team about the benefits of multi-value non-keyword-list attributes
  * Single-value search attribute for non-keyword-list - accepted and returned as given
  * Multi-value search attribute for keyword-list - accepted and returned as given
  * Single-value search attribute for keyword-list - fails
* SQL
  * Multi-value search attribute for non-keyword-list - only allowed if a single value, always returned single value
  * Single-value search attribute for non-keyword-list - accepted and returned as given
  * Multi-value search attribute for keyword-list - accepted and returned as given
  * Single-value search attribute for keyword-list - fails

### Problems with current behavior

* Go and Java rely on user to resolve ambiguity between single and multi value search attributes (Go is worse because it has no helpers)
* TypeScript and Python always disambiguate making all search attributes a list (and Java too in single-value cases) even if list not allowed anymore
* Setting invalid search attributes in workflow never returns a failure that can be handled by workflow code
* Users have no way to clarify the difference between keyword and keyword-list

# Solution 1

(see "Solution 2" for a separate solution)

## Goals

Immediate:

* As much as is supported by the language, users need to be able to get and set individually typed search attributes
* Maintain backwards compatibility but deprecate any approach that doesn't let you identify the search attribute type
  alongside the use of its value

Non-immediate:

* Provide ways to define predefined search attributes that are typed
* Also provide ways to define predefined memo values that are typed

Non-goals:

* Better validation of actual search attribute type from server
* Better way for server to tell SDK the upsert failed
* Support for user-explicit upsert of multiple typed search attributes in one statement
* Support for typed registration of search attributes
* Support for predefined search attributes in any form of query building

## Proposed solution

See "Solution 2" for comparison of approaches

### General

* All SDK workflow APIs will now have a mutable search attribute map with typed getters and setters
  * When a mutation on a search attribute occurs:
    * If the most recent command is an upsert search attribute, the single value is merged
    * If the most recent command is not an upsert search attribute, make one
    * Map is mutated
    * TODO(cretz): How are deletes represented?
* Upsert will be deprecated

### Go

```go
// In client
type SearchAttributes map[string]any

// Yes these already exist today with maps themselves, but clear methods may
// help discourage people from using the map at all. Can remove though.
func (SearchAttributes) Len() int              { panic("TODO") }
func (SearchAttributes) GetKeys() []string     { panic("TODO") }
func (SearchAttributes) HasKey(string) bool    { panic("TODO") }
func (SearchAttributes) DeleteKey(string) bool { panic("TODO") }

func (SearchAttributes) GetText(string) string           { panic("TODO") }
func (SearchAttributes) SetText(string, string)          { panic("TODO") }
func (SearchAttributes) GetKeyword(string) string        { panic("TODO") }
func (SearchAttributes) SetKeyword(string, string)       { panic("TODO") }
func (SearchAttributes) GetInt(string) int               { panic("TODO") }
func (SearchAttributes) SetInt(string, int)              { panic("TODO") }
func (SearchAttributes) GetFloat64(string) float64       { panic("TODO") }
func (SearchAttributes) SetFloat64(string, float64)      { panic("TODO") }
func (SearchAttributes) GetTime(string) time.Time        { panic("TODO") }
func (SearchAttributes) SetTime(string, time.Time)       { panic("TODO") }
func (SearchAttributes) GetKeywordList(string) []string  { panic("TODO") }
func (SearchAttributes) SetKeywordList(string, []string) { panic("TODO") }

// In workflow
func SearchAttributes(Context) SearchAttributes

type SearchAttributes struct{ /*internal stuff */ }

func (SearchAttributes) Len() int              { panic("TODO") }
func (SearchAttributes) GetKeys() []string     { panic("TODO") }
func (SearchAttributes) HasKey(string) bool    { panic("TODO") }
func (SearchAttributes) DeleteKey(string) bool { panic("TODO") }

func (SearchAttributes) GetRawValues() map[string]any { panic("TODO") }

func (SearchAttributes) GetText(string) string           { panic("TODO") }
func (SearchAttributes) SetText(string, string)          { panic("TODO") }
func (SearchAttributes) GetKeyword(string) string        { panic("TODO") }
func (SearchAttributes) SetKeyword(string, string)       { panic("TODO") }
func (SearchAttributes) GetInt(string) int               { panic("TODO") }
func (SearchAttributes) SetInt(string, int)              { panic("TODO") }
func (SearchAttributes) GetFloat64(string) float64       { panic("TODO") }
func (SearchAttributes) SetFloat64(string, float64)      { panic("TODO") }
func (SearchAttributes) GetTime(string) time.Time        { panic("TODO") }
func (SearchAttributes) SetTime(string, time.Time)       { panic("TODO") }
func (SearchAttributes) GetKeywordList(string) []string  { panic("TODO") }
func (SearchAttributes) SetKeywordList(string, []string) { panic("TODO") }
```

Notes:

* There is not a good way to make these generic with this dynamic form (see "Go Later" for one option though)
* Change `StartWorkflowOptions.SearchAttributes` to accept this type
  * I don't want to make this be a `map[string]any` because people will just
    `map[string]interface{} { "key": []int { 1, 2 } }` but this is the only way I can make it backwards compatible. I
    can't even give deprecated warnings when using the raw form at compile time
  * Or do we want to deprecate `StartWorkflowOptions.SearchAttributes` and call this something else?
    `SearchAttributeSet`?
* Deprecate `workflow.Info.SearchAttributes`

#### Go later

Ability to define individual search attributes:

```go
type SearchAttributeText string
func (SearchAttributeText) Exists(Context) bool { panic("TODO") }
func (SearchAttributeText) Get(Context) string  { panic("TODO") }
func (SearchAttributeText) Set(Context, string) { panic("TODO") }
func (SearchAttributeText) Delete(Context)      { panic("TODO") }

type SearchAttributeKeyword string
func (SearchAttributeKeyword) Exists(Context) bool { panic("TODO") }
func (SearchAttributeKeyword) Get(Context) string  { panic("TODO") }
func (SearchAttributeKeyword) Set(Context, string) { panic("TODO") }
func (SearchAttributeKeyword) Delete(Context)      { panic("TODO") }

type SearchAttributeInt string
func (SearchAttributeInt) Exists(Context) bool { panic("TODO") }
func (SearchAttributeInt) Get(Context) int     { panic("TODO") }
func (SearchAttributeInt) Set(Context, int)    { panic("TODO") }
func (SearchAttributeInt) Delete(Context)      { panic("TODO") }

type SearchAttributeFloat64 string
func (SearchAttributeFloat64) Exists(Context) bool  { panic("TODO") }
func (SearchAttributeFloat64) Get(Context) float64  { panic("TODO") }
func (SearchAttributeFloat64) Set(Context, float64) { panic("TODO") }
func (SearchAttributeFloat64) Delete(Context)       { panic("TODO") }

type SearchAttributeTime string
func (SearchAttributeTime) Exists(Context) bool    { panic("TODO") }
func (SearchAttributeTime) Get(Context) time.Time  { panic("TODO") }
func (SearchAttributeTime) Set(Context, time.Time) { panic("TODO") }
func (SearchAttributeTime) Delete(Context)         { panic("TODO") }

type SearchAttributeKeywordList string
func (SearchAttributeKeywordList) Exists(Context) bool   { panic("TODO") }
func (SearchAttributeKeywordList) Get(Context) []string  { panic("TODO") }
func (SearchAttributeKeywordList) Set(Context, []string) { panic("TODO") }
func (SearchAttributeKeywordList) Delete(Context)        { panic("TODO") }
```

Which can be defined and used like:

```go
const MySearchAttribute = SearchAttributeInt("MySearchAttribute")
```

And then used from the workflow. Alternatively we could have something like:

```go
type searchAttributeValueConstraint interface {
	string | int | float64 | time.Time | []string
}

type SearchAttribute[T searchAttributeValueConstraint] string

func (SearchAttribute[T]) Exists(Context) bool { panic("TODO") }
func (SearchAttribute[T]) Get(Context) T       { panic("TODO") }
func (SearchAttribute[T]) Set(Context, T)      { panic("TODO") }
func (SearchAttribute[T]) Delete(Context)      { panic("TODO") }
```

And defined like:

```go
const MySearchAttribute = SearchAttribute[int]("MySearchAttribute")
```

But the former is more explicit probably. This same thing would need to be done for memos but be looser on accepted
types.

### Java

Visibility and method bodies left out for brevity.

```java
public class SearchAttributeMap implements Map<String, Object> {
    // Constructor fails if called in workflow
    SearchAttributeMap()

    @Deprecated
    Object get(Object key);
    @Deprecated
    Object put(String key, Object value);

    String getText(String key);
    String putText(String key, String value);
    String getKeyword(String key);
    String putKeyword(String key, String value);
    Integer getInteger(String key);
    String putInteger(String key, Integer value);
    Double getDouble(String key);
    String putDouble(String key, Double value);
    OffsetDateTime getOffsetDateTime(String key);
    OffsetDateTime putDouble(String key, OffsetDateTime value);
    // Immutable
    List<String> getKeywordList(String key);
    List<String> putKeywordList(String key, List<String> value);
}
```

* Deprecate `WorkflowOptions.Builder.setSearchAttributes`
* Add overload `WorkflowOptions.Builder.setSearchAttributes` that accepts this map type
  * The ability to need to instantiate this is why it's a class and not an interface
    * Could have this be an interface if it was also easy to create somehow
* Deprecate `Workflow.getSearchAttributes`, `Workflow.getSearchAttribute`, and `Workflow.getSearchAttributeValues`
  * Can't think of a better way here, we can't reuse these from my POV and still be compat
* Add `Workflow.getSearchAttributeMap` that returns this
  * This is mutable! Mutations follow general rules laid out before
* Should we log a runtime warning if they use the Map accessors directly?
* Change workflow list search attribute result to return this

#### Java later

Can make annotation like so:

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
public @interface WorkflowSearchAttribute {
  public String value();
}

public interface SearchAttribute<T> {
  boolean exists();
  T get();
  void put(T);
  void delete();
}

public class SearchAttributeInt implements SearchAttribute<Integer> {
  // Package private constructor
  SearchAttributeInt()
}
```

And use it like

```java
public class MyWorkflowImpl implements MyWorkflow {
    @WorkflowSearchAttribute("my-search-attribute")
    private SearchAttributeInt mySearchAttribute;

    // ...
}
```

Notes:

* Considered making it a static field on the workflow interface so that it could be somehow usable outside the impl
  * But once I realized I wanted the mutation methods on the impl, it became clear this is impl-time only I think
  * Also, since impl time only, I can put the name in the annotation instead of having a search attribute constructor
  * Is this ok to do for us to populate this field reflectively after construction and promise always non-null, or
    should we require that they instantiate,
    e.g. `private final SearchAttributeInt mySearchAttribute = new SearchAttributeInt();`?
  * Is there a good use case to have this definition usable externally via static field on interface instead?
* Do same thing for memos but allow looser types

### TypeScript

Being la

```typescript
type SearchAttributeValue = string[] | number[] | boolean[] | Date[] | string | number | boolean | Date
interface SearchAttributes extends Record<string, SearchAttributeValue> {
  /**
   * @deprecated
   */
  [key: string]: SearchAttributeValue

  // Yes these two are available for normal objects, but the idea of the
  // presence of these methods is to discourage using object properties. Can
  // remove though.
  hasKey(key: string): bool
  deleteKey(key: string)

  getText(key: string): string?
  setText(key: string, value: string?)
  getKeyword(key: string): string?
  setKeyword(key: string, value: string?)
  getInteger(key: string): number?
  setInteger(key: string, value: number?)
  getFloat(key: string): number?
  setFloat(key: string, value: number?)
  getDate(key: string): Date?
  setDate(key: string, value: Date?)
  getKeywordList(key: string): string[]?
  setKeywordList(key: string, value: string[]?)
}
```

Notes:

* Is it possible to add methods like this without messing up everyone's `for in` or `Object.entries()`?
  * I know we could be smarter about the types from the indexer but I think the getters/setters are clearer
* Should we issue a runtime warning for use of the index based accessor?
* Replace all current uses of search attributes with this type
  * But still accept raw records for input, in deprecated overloads if possible
* Deprecate `upsertSearchAttributes`

#### TypeScript later

What's at https://github.com/temporalio/proposals/pull/67 mostly. Here's a snippet:

```typescript
import { defineAttribute, Keyword, Text } from '@temporalio/common/search-attributes'

export const tagsAttribute = defineAttribute(Keyword, 'tags')
export const customerAttribute = defineAttribute(Text, 'customer')
export const dateOfPurchaseAttribute = defineAttribute(Date, 'dateOfPurchase')

// ...

const customer = customerAttribute.value()
const tags = tagsAttribute.value()
dateOfPurchaseAttribute.set(new Date())
dateOfPurchaseAttribute.unset()
```

Notes:

* Not sure there is value in exporting this anytime soon
  * APIs meant only for use on a workflow are defined on this, it's not general purpose
  * Same situation with Go and Java and Python
* Do we like `unset` or `delete`?

### Python

```python
type SearchAttributeValues = Union[
    str, int, float, bool, datetime,
    List[str], List[int], List[float], List[bool], List[datetime],
]

class SearchAttributes(Mapping[str, SearchAttributeValues]):
    # ... Deprecate all existing accessors ...

    def get_text(self, key: str) -> str: ...
    def set_text(self, key: str, val: str) -> None: ...
    def get_keyword(self, key: str) -> str: ...
    def set_keyword(self, key: str, val: str) -> None: ...
    def get_int(self, key: str) -> int: ...
    def set_int(self, key: str, val: int) -> None: ...
    def get_float(self, key: str) -> float: ...
    def set_float(self, key: str, val: float) -> None: ...
    def get_datetime(self, key: str) -> datetime: ...
    def set_datetime(self, key: str, val: datetime) -> None: ...
    def get_keyword_list(self, key: str) -> Sequence[str]: ...
    def set_keyword_list(self, key: str, val: Sequence[str]) -> None: ...
```

* Replaces all places of search attributes today
  * But we still accept mapping input deprecated overload
* `upsert_search_attributes` deprecated

#### Python later

Maybe a decorator like:

```python

def search_attribute(field, *, name: Optional[str] = None):
    ...
```

Used like:

```python
@workflow.defn
class MyWorkflow:
    @workflow.search_attribute
    my_search_attribute: int

    @workflow.run
    async def run(self) -> None:
        ...
```

Notes:

* Since Python can override getters and setters, this becomes an neat approach
* We may need some way to obviously unset and to see if the attribute exists
  * Probably support `Optional[X]` forms they can check or set to `None`
  * Probably also have `delete()` and `is_set()` or similar

### .NET

```csharp
class SearchAttributes
{
    public int Count { get; }
    public IEnumerable<string> Keys { get; }
    public bool ContainsKey(string key);
    public void Remove(string key);

    public string GetText(string key);
    public bool TryGetText(string key, out string value);
    public void SetText(string key, string value);
    public string GetKeyword(string key);
    public bool TryGetKeyword(string key, out string value);
    public void SetKeyword(string key, string value);
    public int GetInt(string key);
    public bool TryGetInt(string key, out int value);
    public void SetInt(string key, int value);
    public double GetDouble(string key);
    public bool TryGetDouble(string key, out double value);
    public void SetDouble(string key, double value);
    public DateTime GetDateTime(string key);
    public bool TryGetDateTime(string key, out DateTime value);
    public void SetDateTime(string key, DateTime value);
    public IReadOnlyCollection<string> GetKeywordList(string key);
    public bool TryGetKeywordList(string key, out IReadOnlyCollection<string> value);
    public void SetKeywordList(string key, IReadOnlyCollection<string> value);
}
```

Notes:

* We cannot have a dictionary here because there's no reasonable type for the value that doesn't result in misuse
  * Yes this means it's much less usable in ways collections are usually used. That is accepted.

#### .NET later

Attribute based property, e.g.

```csharp
[AttributeUsage(AttributeTargets.Field, Inherited = false)]
public class WorkflowSearchAttributeAttribute : Attribute
{
    public SearchAttributeAttribute(string name) { }
}
```

Used like:

```csharp
[Workflow]
public class MyWorkflow
{
    [WorkflowSearchAttribute]
    private readonly SearchAttributeInt mySearchAttribute = new();
}
```

# Solution 2

## Goals

Immediate:

* As much as is supported by the language, users need to be able to individually define search attributes but must still
  be able to set them altogether
* Maintain backwards compatibility but deprecate any approach that doesn't require predefining attributes

Non-goals:

* Flexible API
* Better validation of actual search attribute type from server
* Better way for server to tell SDK the upsert failed
* Support for easy/non-multi form of setting single attribute values
* Support for typed registration of search attributes
* Support for any form of query building

## Proposed solution

### General

* Client and workflow APIs using untyped maps are deprecated and will be replaced with opaque typed collections (via
  overloads where able) where keys are predefined search attributes
* Upsert is used

Differences between "Solution 1":

* This retains the concept of upsert multi
* This removes the idea of single-attribute setting
* This uses typed "keys" in collections (where available) instead of separate single-value mutations
* API is a little less friendly at the expense of safety
* History compatibility is retained (assuming we aren't checking contents of upsert)

Option 1 below:

* Find a new name for "searchAttributes" as used in code and deprecate where used

Option 2 below:

* Reuse mapping/collection type of existing search attributes

### Go

```go
package temporal

type searchAttributeKey interface { keyType() enums.IndexedValueType }

type SearchAttributeValue struct{}

type SearchAttributesReadOnly interface{
  // Always sorted
  Keys() []string

  toProto() *common.SearchAttributes
}

type SearchAttributes struct{}

func (*SearchAttributes) Keys() []string

// These represent keys
type SearchAttributeText string
type SearchAttributeKeyword string
type SearchAttributeInt string
type SearchAttributeFloat64 string
type SearchAttributeTime string
type SearchAttributeKeywordList string

func (SearchAttributeText) keyType() enums.IndexedValueType
func (SearchAttributeText) IsSet(SearchAttributesReadOnly) bool
func (SearchAttributeText) GetValue(SearchAttributesReadOnly) string
func (SearchAttributeText) SetValue(*SearchAttributes, string)
func (SearchAttributeText) DeleteValue(*SearchAttributes)

// ... Each set of 5 methods for each type, with the get/set as the proper type

// --- For client option 1 ---

type StartWorkflowOptions struct {
  // ...

	// Deprecated: Use SearchAttributeSet instead
  //
  // TODO(cretz): Maybe a better option is to have this accept "any" and warn
  // when a map is used instead of a search attribute set?
	SearchAttributes   map[string]any

	SearchAttributeSet SearchAttributesReadOnly
}

// --- For client option 2 ---

type StartWorkflowOptions struct {
  // This must be SearchAttributesReadOnly or a map. Maps are deprecated and
  // this will warn if a map is used.
  SearchAttributes any
}

// --- For workflow

// This is updated as upsert/apply is invoked
func GetSearchAttributes(Context) SearchAttributesReadOnly

// --- For workflow option 1 ---

// Deprecated: Use ApplySearchAttributes instead
func UpsertSearchAttributes(Context, map[string]interface{}) error

// Future resolved with error on failure
func ApplySearchAttributes(Context, SearchAttributesReadOnly) error

// --- For workflow option 2 ---

// Accepts SearchAttributesReadOnly or a map. Maps are deprecated and this will
// warn if a map is used.
func UpsertSearchAttributes(Context, any) error
```

Workflow usage like:

```go
const MySearchAttribute = temporal.SearchAttributeInt("MySearchAttribute")

func MyWorkflow(ctx workflow.Context) error {
  attrs := workflow.GetSearchAttributes(ctx)
  workflow.GetLogger(ctx).Info(
    fmt.Sprintf("Orig attr value: %v", MySearchAttribute.GetValue(attrs)))
  
  // If using option 2
  var newAttrs SearchAttributes
  MySearchAttribute.SetValue(&newAttrs, 456)
  if err := workflow.UpsertSearchAttributes(ctx, &newAttrs); err != nil {
    return err
  }
  
  workflow.GetLogger(ctx).Info(
    fmt.Sprintf("New attr value: %v", MySearchAttribute.GetValue(attrs)))
  return nil
}
```

Client usage like:

```go

// ...

var attrs temporal.SearchAttributes
MySearchAttribute.SetValue(&attrs, 123)

myClient.ExecuteWorkflow(... client.StartWorkflowOptions {
  // If using option 2
  SearchAttributes: &attrs,
})
```
}

Notes:

* Which client option, 1 or 2?
* Which workflow option, 1 or 2?
* Will people get too annoyed with "warnings"? Need way to disable those?
* What package should the attr types be in? In the `temporal` package can be less discoverable to workflow users and in the
  `workflow` package can be less discoverable to client users (`client` package is obviously a no-no for workflow users)

### Java

(TODO: expand to code)

Idea:

* Have `SearchAttributeX` classes like Go for each SA type that have hashCode impls for their class + key name
  * Expected to be used like `SearchAttributeInt MY_SEARCH_ATTR = new SearchAttributeInt("MySearchAttribute")` in
    workflow interface (or as `public static final` in a class somewhere)
  * Each generically implements `SearchAttributeKey<T>`
* Have `ImmutableSearchAttributes` interface that has:
  * `SortedSet<String> keys()`
  * `@Nullable T get<T>(SearchAttributeKey<T>)`
  * `bool containsKey(SearchAttributeKey<?>)`
  * `int size()`
* Have new `SearchAttributes` class that impls `ImmutableSearchAttributes` and is a collection but does not extend any
  impl collection interface
  * _Could_ impl `List<SearchAttribute>`, but the code gets a bit ugly (set or map have limited value here though)
  * Has `void put<T>(SearchAttributeKey<T>, @Nonnull T)`
  * Has `void remove(SearchAttributeKey<?>)`
  * This must be user instantiable
* Option 1
  * For client:
    * Deprecate builder `setSearchAttributes` and options `getSearchAttributes`
    * Add builder `setSearchAttributeSet(ImmutableSearchAttributes)` and options `getSearchAttributeSet`
      * Is this too annoying to have a "SearchAttributeSet"?
      * Better name? `ImmutableSearchAttributes`, `InitialSearchAttributes`, `SearchAttributeValues`, etc?
    * Add overload for builder `setSearchAttributes(ImmutableSearchAttributes)`
      * Why have this if we have the other setter?
  * For workflow:
    * Deprecate all existing
    * Add `ImmutableSearchAttributes getSearchAttributeSet()`
    * Add `upsertSearchAttributeSet(ImmutableSearchAttributes)`
    * Add overload `upsertSearchAttributes(ImmutableSearchAttributes)`
      * Why have this overload if we have the other method?
* Option 2
  * Have `ImmutableSearchAttributes` extend `SortedMap<String, List<Object>>`
    * Don't support any mutation
    * Deprecate/warn the best we can on any value-getting
  * Deprecate all functions that accept maps and add overloads to those to accept `ImmutableSearchAttributes`
  * Change all functions that return search attribute map today to return `ImmutableSearchAttributes`
    * This safe/allowed?
  * Deprecate all other calls

### TypeScript

(TODO: expand to code)

Similar to https://github.com/temporalio/proposals/pull/67. Idea:

* Have way to define search attribute by type and give key name
* Have immutable search attributes interface that supports common read-only collection things for attributes as keys
  * Cannot use index accessor of course since that's limited in JS, so have getter accepting user-defined SA
* Have mutable search attributes user can build up that are passed to client options or workflow upsert
  * Need non-index-accessor setter same as getter
* Option 1:
  * Call it something besides `searchAttributes` like `searchAttributeValues` and deprecate all the `searchAttributes`
    ones
* Option 2:
  * Where `Record<string, scalar[]>` is accepted today, deprecate and overload with immutable type
  * Where `Record<string, scalar[]>` is returned today, change to `ImmutableSearchAttributes | Record<string, scalar[]>`
    and deprecate use of index accessor on result

### Python

(TODO: expand to code)

* Same as TS basically except below
* Option 2:
  * We can change our `Mapping` key to `Union[str, SearchAttributeKey]` but we still can't have backwards compatible
    `__getitem__` that still has new stuff

### .NET

(TODO: expand to code)

* Have `SearchAttributes` impl `ICollection<SearchAttribute>` and `IReadOnlySearchAttributes`
* No backwards compatibility concerns, so will have to see how the others shake out