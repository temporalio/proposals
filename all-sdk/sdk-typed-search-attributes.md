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

* Go and Java rely on user to resolve ambiguity between single and multi value search attributes (Go is worse because
  it has no helpers)
* TypeScript and Python always disambiguate making all search attributes a list (and Java too in single-value cases)
  even if list not allowed anymore
* Setting invalid search attributes in workflow never returns a failure that can be handled by workflow code
* Users have no way to clarify the difference between keyword and keyword-list

## Solution

Problems that we have to overcome:

* The "search attribute" term is already taken, so we have to have a new name or return a form of the same type
* Upsert has no easy way of determining what is a delete. Today it is using null-ness.

### Non-solution

It was decided that it is unreasonable to extend/wrap existing collection types to reuse the "search attribute" name
because:

* Leaving the existing untyped accessors on the same collection would not encourage anyone to move
* It is hard for us to deprecate untyped accessors in favor of typed ones

### Details

* We have decided to create a new strict collection called `SearchAttributes`
  * This does not extend/use any existing collection interface in the language
    * The collection would have to be a raw tuple because when getting from a server we can't type on a per key basis
    * If we reused an existing collection interface, people would be encouraged to use it which has to remove typing
      (no language has a good way to represent a collection of values whose types are dependent on their specific key)
    * We are gonna make the raw values available via getter instead of on the collection
      * We don't want people to have language native collection iteration abilities on this or they'll be working with
        untyped tuples
  * We considered calling this collection `TypedSearchAttributes` (and lang can if disambiguation needed), but not
    wanted
  * This collection is read only and languages can provide ways to create it with type-safe key-values the best they can
    * Go, Java, Python, and .NET may use a builder, TS may use tuple construction
  * The collection should have:
    * A single typed getter for getting typed values given a `SearchAttributeKey`
      * In Go where methods cannot have generics, this may have to be inverted to add the getter on the attribute
        definition
    * Ability to determine if key is present and total count in collection
    * Ability to retrieve a read-only (ideally sorted or deterministically ranged) collection of raw key/value
      string/object tuples
      * This needs an unwieldy name like `getRawValues()`
    * A builder with a copy constructor
* There is a new generic base type of `SearchAttributeKey`
  * Instantiations of this class with certain things can be done via static helpers
  * These are just for predefining known search attribute keys and their types
  * The `SearchAttributeInt`, `SearchAttributeDouble`, and `SearchAttributeTime` should be named according to language
    types. So Go may use `SearchAttributeFloat64`, Java may use `SearchAttributeKey.OffsetDateTime`, etc
  * This is expected to be used in top-level consts. So Java might have
    `public static final SearchAttributeKey<Integer> MY_ATTR = new SearchAttributeKey.forInteger("myAttr")` (or can be
    just in the workflow interface), Go might have `const MyAttr = SearchAttributeKeyInt("myAttr")`, etc
* We are calling these "typed search attributes" for user getters/setters
  * It was considered to just overload client options set and workflow upsert to accept old or new type, but that
    doesn't help getters (can't overload the return and union is unclear to users and hard to deprecate)
  * It was considered to just move the getter from workflow package/namespace to workflow info object and vice versa,
    but this became confusing (in Go they are already on info, in Java they are on workflow context not info, etc)
  * It was considered to make this just "search attributes" and find ways per language to cheat that (e.g. in Java
    `Workflow.getSearchAttributes` would be deprecated in favor of `Workflow.searchAttributes`)
    * This becomes really difficult and inconsistent across languages
  * Other names considered were:
    * "workflow search attributes" - doesn't work for schedules
    * "search attrs" - hard to justify abbreviation
    * "attributes" - not acceptable to how Temporal uses the "search attributes" term everywhere
* All existing forms of search attribute getting and setting are hereby deprecated
* Client options will have ability to get/build this collection as "typed search attributes"
* Workflows can get a read-only form of this collection (however lang expresses that best) as "typed search attributes"
  getter at the top of the workflow adjacent to where getting "info" is today
* "upsert search attributes" is deprecated
  * We could have overloaded this in all languages but Go, but clearer to stay with the "typed search attribute" term
* "upsert typed search attributes" is made available on the workflow level where "upsert" already exists today
  * Considered calling "update" or "apply" instead of "upsert", but decided that while "upsert" doesn't represent unset
    properly, it matches the event name that users see in the UI
  * This accepts a vararg `SearchAttributeUpdate` that is either a "set" or an "unset"
    * We accept this is ugly, but there is no better way to represent deletes
    * We considered a mutable `SearchAttributes` collection but individual key/value mutations would be too hard to
      reason about if buffered/batched and if single upsert commands people would ask for bulk as soon as individual
      upsert events appeared
    * Each `SearchAttributeKey` has a `valueSet(value)` and a `valueUnset()` that return `SearchAttributeUpdate`s
      * So Java may look like `Workflow.updateSearchAttributes(MY_ATTR1.valueSet("foo"), MY_ATTR2.valueUnset())`
      * We intentionally are calling adding "value" prefix instead of just `set` and `unset` to make it clear the key
        is providing a value update
  * Since we are not offering an async error for this, this function should return the equivalent of
    "get typed search attributes"

## Usage Examples

### Java

Public API (this is approximate and untested, just typed here in proposal to get an idea).

Impl:

```java
/** Immutable **/
public class SearchAttributes {
  @Nonnull
  public T get<T>(SearchAttributeKey<T> key) {
    // ...
  }

  public boolean containsKey(SearchAttributeKey<T> key) {
    // ...
  }

  public SortedMap<String, Object> getRawValues() {
    // ...
  }

  public int size() {
    // ...
  }

  public static Builder newBuilder() {
    // ...
  }

  public static Builder newBuilder(SearchAttributes toCopy) {
    // ...
  }

  public static class Builder {
    public Builder set<T>(SearchAttributeKey<T> key, @Nonnull T value) {
      // ...
    }

    public Builder unset(SearchAttributeKey<?> key) {
      // ...
    }

    public Builder setUntyped(String key, Object value) {
      // ...
    }

    public Builder unsetUntyped(String key) {
      // ...
    }

    public SearchAttributes build() {
      // ...
    }
  }
}

public abstract class SearchAttributeKey<T> {
  SearchAttributeKey(String name, Class<T> valueType) {
    // ...
  }

  public String getName() {
    // ...
  }

  public Class<T> getValueType() {
    // ...
  }

  public SearchAttributeUpdate valueSet(@Nonnull T value) {
    // ...
  }

  public SearchAttributeUpdate valueUnset() {
    // ...
  }

  public static SearchAttributeKey<List<String>> forKeywordList(String name) {
    // ...
  }

  public static SearchAttributeKey<Integer> forInteger(String name) {
    // ...
  }

  // etc

  static class KeywordList extends SearchAttributeKey<List<String>> {
    KeywordList(String name) {
      // TODO(cretz): Use Guava type token instead of class to capture generic?
      super(name, List.class);
    }
  }

  static class Integer extends SearchAttributeKey<Integer> {
    Integer(String name) {
      super(name, Integer.class);
    }
  }

  // etc
}

public abstract class SearchAttributeUpdate {
  SearchAttributeUpdate(String key) { }

  public static SearchAttributeUpdate valueSetUntyped(String key, Object value) {
    // ...
  }

  public static SearchAttributeUpdate valueUnsetUntyped(String key) {
    // ...
  }

  static class Set extends SearchAttributeUpdate {
    // Unfortunately has to be public for untyped use. But
    Set(String key, Object value) {
      super(key);
      // ...
    }
  }

  static class Unset extends SearchAttributeUpdate {
    Unset(String key) {
      super(key);
      // ...
    }
  }
}

// For workflows
public class Workflow {
  // ... after other existing stuff including deprecated calls ...

  public SearchAttributes getTypedSearchAttributes() {
    // ...
  }

  public SearchAttributes upsertTypedSearchAttributes(SearchAttributeUpdate... updates) {
    // ...
  }
}

// For clients
public class WorkflowOptions {
  // ... after other existing stuff including deprecated calls ...

  public SearchAttributes getTypedSearchAttributes() {
    // ...
  }

  public static class Builder {
    // ... after other existing stuff including deprecated calls ...

    /** Exception thrown if this and search attributes both present */
    public Builder setTypedSearchAttributes(SearchAttributes attributes) {
      // ...
    }
  }
}
```

Usage:

```java
public interface MyWorkflow {
  SearchAttributeKey<Integer> MY_ATTR = new SearchAttributeKey.forInteger("my-attr-name");

  // ...
}

// Client usage
public class Main {
  public static void main(String[] args) {
    // ...

    var workflow = client.newWorkflowStub(
        MyWorkflow.class,
        WorkflowOptions.newBuilder()
            .setWorkflowId("my-id")
            .setTaskQueue(taskQueue)
            .setTypedSearchAttributes(SearchAttributes
              .newBuilder()
              .set(MyWorkflow.MY_ATTR, 123)
              .build())
            .build()
        );

    // ...
  }
}

// Inside workflow usage
public class MyWorkflowImpl implements MyWorkflow {
  
  @Override
  public void run() {
    // ...

    logger.info("Orig search attr: {}", Workflow.getTypedSearchAttributes().get(MY_ATTR));

    Workflow.upsertTypedSearchAttributes(MY_ATTR.valueSet(456));

    logger.info("New search attr: {}", Workflow.getTypedSearchAttributes().get(MY_ATTR));

    // ...
  }
}
```