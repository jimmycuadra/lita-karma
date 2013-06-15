# lita-karma

**lita-karma** is a handler for [Lita](https://github.com/jimmycuadra/lita) that tracks karma points for arbitrary terms. It listens for upvotes and downvotes and keeps a tally of the scores for them in Redis.

## Installation

Add lita-karma to your Lita instance's Gemfile:

``` ruby
gem "lita-karma"
```

## Usage

Lita will add a karma point whenever it hears a term upvoted:

```
term++
```

It will subtract a karma point whenever it hears a term downvoted:

```
term--
```

To check the current karma for a term without modifying it:

```
term~~
```

To list the top scoring terms:

```
Lita: karma
```

To list the worst scoring terms:

```
Lita: karma worst
```

These commands will list 5 terms by default. To specify a number, pass a second argument to the karma command:

```
Lita: karma best 10
```

You can also link terms together. This adds one term's karma to another's whenever it is displayed. A link is uni-directional and non-destructive. You can unlink terms at any time.

```
foo++
> foo: 1
bar++
> bar: 1
Lita: foo += bar
> bar has been linked to foo.
foo~~
> foo: 2
bar~~
> bar: 1
Lita: foo -= bar
> bar has been unlinked from foo.
foo~~
> foo: 1
```

## License

[MIT](http://opensource.org/licenses/MIT)
