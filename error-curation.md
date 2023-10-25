# Error Curation

## Overview

Many errors occur in Temporal yet pithy error messages alone are not enough to give context. We need to provide
easy-to-reference identifiers to each and pages on each to help.

**Goals**

These are goals for the error curation project, not this proposal in particular though there is overlap.

* Document requirements for rule numbering/identification
* Document requirements for rule documenting
* Provide home for all rule documents
* Build initial set of rules for use in SDKs

**Non-Goals**

* Document every error
* Make the error documents available on docs.temporal.io at first
* Provide any UX linking errors from UI, CLI, etc
* Extremely strict documentation guidelines

## Approach

This approach is inspired by .NET analyzers which have coded values and dedicated pages for each error. For example,
see:

* https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/categories (e.g.
  https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1001)
* https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/DOCUMENTATION.md (e.g.
  https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/SA1200.md)
* https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/index.md (e.g.
  https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/VSTHRD003.md)

Solution:

* A "rule" is referenceable, documented error/warning/note/guideline
* We are calling these "rules" not "errors"
  * They may be found eagerly, may just be disable-able warnings, or may even be just best practice rules
* Rules can be for many things:
  * Errors (e.g. SDK errors, static analysis errors, server errors, etc)
  * Guidelines (e.g. best practices, warnings, etc)
* Every rule has an identifier in the form of `TMPRLXXXX`
  * "Categories" of rules are given a 100 block as rarely is more needed
    * Category 100 blocks should try not to be next to another so space can be given in some rare case we exceed 100 in
      a category
    * There are no rules on what a category is, just a grouping of like things
  * The rules within a category do not have to be ordered in any manner. Usually you just use the next available.
  * `0` is never used in the first two digits
  * Can discuss the first thousands-block digit though initial thought for first two is:
    * `TMPRL1XXX` block is for SDK-specific and workflow/activity authoring things
    * `TMPRL2XXX` block is for server-specific and operation things
* Rule/error messages across Temporal should be prepended with `"[TMPRLXXXX] "` (sans quotes)
  * Note the brackets and space after.
  * We are intentionally not providing a stricter requirement than this. There is intentionally no requirement to make
    these available for programmatic consumption and we are not even going to guarantee these are even present or there
    is a stable URL to learn more.
  * SDK, gRPC API and other programmatic places where errors occur do not need to go out of their way to separate this
    from the message string. There is limited value. From POV of code, this might as well be the beginning of an English
    sentence and no more. Forcing stricter format/abstraction is more cost than benefit.
* All rules are housed in a single repository
  * Maybe something like https://github.com/temporalio/temporal-rules https://github.com/temporalio/rule-library
  * `rules/README.md` will be the primary index of all categories
  * `rules/TMPRL11XX.md` with the literal `XX.md` suffix but the two-digit category will be the index of all rules in
    that category
  * `rules/TMPRL1234.md` will be the literal page
    * Consideration was given to breaking these out into subdirectories, but experience has shown a nice, common
      `https://github.com/temporalio/temporal-rules/blob/main/rules/<RULE_NUM>.md` URL for _all_ rules has a lot of
      benefits
  * This project does not concern itself with the eventual promotion of this content to regular docs, just that it needs
    to be in a repository for review/submission by Temporal developers
* The `rules/TMPRL1234.md` file will contain rule details
  * No strict metadata/frontmatter required at this time
  * Ideally the rules may have at the following headings (but license is given to author to format as needed):
    * `# <TMPRL1234> - <one-sentence-description>`
    * `## Cause`
    * `## Description`
      * Only if cause is not enough information
    * `## Remediations`
      * Chosen over "Solutions" as not everything will be solvable
  * More headings can be added
  * None of the contents/headings are strict/rigid/required, they are just suggestions
  * Authors are encouraged to get as detailed as they'd like with code snippets, stable links, hypotheticals, use cases,
    etc
* The SDKs will be crawled for error/warning messages, and have ones that are categorizable/documentable errors will be
  cataloged as rules, be given identifiers, have rule pages created, and have the strings prepend the identifiers
  * Note, initial version of the project may only do some of these
* Static analyzers (of which we only have one at the moment) will be updated with rules similar to SDKs above