- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Unified pagination tooling
In the current tctl each command that wants to use pagination has to implement it from scratch. This also leads to incostistent behavior between commands. 
Create a unified pager tooling for easy integration and consistent UX. The utility should also support piping into other tools.

Usage syntax of the unified tooling:
``` go
# create iterator over your data
iterator := collection.NewPagingIterator(paginationFunc)

# specify fields to print and optionally few other options (default formatting as Table or JSON?)
options := &format.PrintOptions{
  Fields: []string{"Execution.WorkflowId", "Execution.RunId", "StartTime"}  
}

# start pager printing process (or fallback to os.Stdout)
format.Paginate(cliContext, iterator, options)
```

### UX & Performance improvement over large sets of data
1. Piping into other tools may create performance issues on large sets of data, since you have to pre-fetch all data and only then pass into a pipe.

By direct integration of piping into pagers (`less`, `more`) we can improve performance since we get to benefit from lazy loading and fetching more data only when it's needed.
This also improves the default pagination UX by using proved tools and follows UNIX philosophy.

Examples:
Page over items with `less`
```bash
tctl workflow list --pager less # default behavior for Table view
```
Page over items with `more`
```bash
tctl workflow list --pager more # default behavior for JSON and Card views
```

### Any custom pagers
Allow users to provide their own favorite pagers

Example
```bash
tctl workflow list --pager myFavoritePager

tctl workflow list --pager bat
```
