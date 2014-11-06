# lita-karma

[![Build Status](https://travis-ci.org/jimmycuadra/lita-karma.png?branch=master)](https://travis-ci.org/jimmycuadra/lita-karma)
[![Code Climate](https://codeclimate.com/github/jimmycuadra/lita-karma.png)](https://codeclimate.com/github/jimmycuadra/lita-karma)
[![Coverage Status](https://coveralls.io/repos/jimmycuadra/lita-karma/badge.png)](https://coveralls.io/r/jimmycuadra/lita-karma)

**lita-karma** is a handler for [Lita](https://github.com/jimmycuadra/lita) that tracks karma points for arbitrary terms. It listens for upvotes and downvotes and keeps a tally of the scores for them in Redis.

## Installation

Add lita-karma to your Lita instance's Gemfile:

``` ruby
gem "lita-karma"
```

## Configuration

### Optional attributes

* **cooldown** (`Integer`, `nil`) - Controls how long a user must wait after modifying a term before they can modify it again. The value should be an integer number of seconds. Set it to `nil` to disable rate limiting. Default: `300` (5 minutes).
* **link_karma_threshold** (`Integer`, `nil`) - Controls how many points a term must have before it can be linked to other terms or before terms can be linked to it. Treated as an absolute value, so it applies to both positive and negative karma. Set it to `nil` to allow all terms to be linked regardless of karma. Default: `10`.
* **term_pattern** (`Regexp`) - Determines what Lita will recognize as a valid term for tracking karma. Default: `/[\[\]\p{Word}\._|\{\}]{2,}/`.
* **term_normalizer** (`#call`) - A custom callable that determines how each term will be normalized before being stored in Redis. The proc should take one argument, the term as matched via regular expression, and return one value, the normalized version of the term. Default: turns the term into a string, downcases it, and strips whitespace off both ends.
* **decay** (Boolean) - When true, karma will slowly decay over time. Default: `false`.
* **decay_interval** (`Integer`) - The time interval (in seconds) after which karma should decay. Default: `2592000` (30 days).
* **decay_distributor** (`#call`) - A custom callable that defines how karma changes from the same user are distributed in time when upgrading an existing installation to use decay. It takes the configured decay interval, an index, and an item count as arguments, and returns the number of seconds to subtract from current time. See [Karma decay](#karma-decay) below.
* **upgrade_modified** (`#call`) - A custom callable that upgrades the modified list for a given term. It should take two arguments: the score and a list of user IDs. It should return a list in the form of `[[score_1, user_id_1], ...]`. See [Modification counts](#modification-counts) below.

### Example

This example configuration sets the cooldown to 10 minutes, turns on decay (karma decays after 5 days), and changes the term pattern and normalization to allow multi-word terms bounded by `<>` or `:`, as previous versions of lita-karma did by default.

``` ruby
Lita.configure do |config|
  config.handlers.karma.cooldown = 600
  config.handlers.karma.decay = true
  config.handlers.karma.decay_interval = 5 * 24 * 60 * 60
  config.handlers.karma.term_pattern = /[<:][^>:]+[>:]/
  config.handlers.karma.term_normalizer = lambda do |term|
    term.to_s.downcase.strip.sub(/[<:]([^>:]+)[>:]/, '\1')
  end
end
```

## Usage

### Giving Karma

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

### Listing Karma

To list the top scoring terms:

```
Lita: karma best
```

or simply:

```
Lita: karma
```

To list the worst scoring terms:

```
Lita: karma worst
```

The list commands will list 5 terms by default. To specify a number (no greater than 25), pass a second argument to the karma command:

```
Lita: karma best 10
```

### Linking Terms

You can also link terms together. This adds one term's karma to another's whenever it is displayed. A link is uni-directional and non-destructive. You can unlink terms at any time.

```
foo++
> foo: 1
bar++
> bar: 1
Lita: foo += bar
> bar has been linked to foo.
foo~~
> foo: 2 (1), linked to: bar: 1
bar~~
> bar: 1
Lita: foo -= bar
> bar has been unlinked from foo.
foo~~
> foo: 1
```

When a term is linked, the total karma score is displayed first, followed by the score of the term without its linked terms in parentheses.

### Modification lists

To get a list of the users who have upvoted or downvoted a term, and how many times they have modified it:

```
Lita: karma modified foo
> Joe (2), Amy (1)
```

### Deleting Terms

To permanently delete a term and all its links:

```
Lita: karma delete TERM
```

Note that when deleting a term, the term will be matched exactly as typed, including leading whitespace (the single space after the word "delete" is not counted) and other patterns which would not normally match as a valid term. This can be useful if you decide to change the term pattern or normalization and want to clean up previous data that is no longer valid. Deleting a term requires the user to be a member of the `:karma_admins` authorization group.

## Modification counts

Prior to verison 3.1.0, lita-karma only tracked which users had modified a term, but not how many times they had.

When upgrading an installation with existing karma data the modification lists are all automatically upgraded to add counts. The default behavior is to give each modifier one change, regardless of the current score.

This behavior is customizable via the `upgrade_modified` callable invoked on the first startup after the upgrade. For example, to distribute the changes evenly among the existing modifiers:

``` ruby
Lita.configure do |config|
  config.handlers.karma.upgrade_modified = lambda do |score, user_ids|
    user_ids.each_with_index.map do |uid, i|
      [score / user_ids.size + (i < score % size ? 1 : 0), uid]
    end
  end
end
```

The `upgrade_modified` callable is used only *ONCE* (per term) on the first launch after the upgrade to >= 3.1.0.

## Karma decay

As of version 3.1.0, lita-karma can age karma changes out over time. When enabled, as the `decay_interval` seconds pass, karma changes disappear, and the term will eventually return to 0 if no further changes are made to it.

By default the upgrade uses an asymptotic function on the actions of a given user that will cause decay to start slowly but accellerate over time. The more actions for the given user, the softer the curve.

The creation times of these actions are configurable, using the `decay_distributor` Proc. For example, to set all of the creation times to the upgrade time:

```ruby
Lita.configure do |config|
  config.handlers.karma.decay = true
  config.handlers.karma.decay_interval = 30 * 24 * 60 * 60
  config.handlers.karma.decay_distributor = lambda do |decay_interval, index, item_count|
    # decay_interval: the value of config.handlers.karma.decay_interval.
    # item_count: the total number of actions to be created in this batch.
    # index: the current index into that count.

    # This Proc should return the number of seconds to subtract from the
    # current time. (Setting them all to 0 will cause them all to have now as
    # their creation time)

    0
  end
end
```

The `decay_distributor` callable is used only *ONCE* on the first launch after the upgrade to >= 3.1.0.

## License

[MIT](http://opensource.org/licenses/MIT)
