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

