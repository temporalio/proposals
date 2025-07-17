- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Better coloring

Commands should have concrete examples of usage in the help output.

For example, typing `tctl namespace update --help` should have an example in the output, among the lines of

```
...
<help output mentioning arguments, flags etc..>
Examples
    $ tctl namespace update --namespace default --description 'my namespace new description'
    $ tctl namespace update --namespace default --retention 3
```
