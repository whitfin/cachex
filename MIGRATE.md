# Migrating v1.x to v2.x

If anything is not covered in here, or there are any issues with anything written in here, please file an issue and I'll get it taken care of.

- [Distribution](#distribution)
- [Fallbacks](#fallbacks)
- [Hook Interface](#hook-interface)
  - [Callbacks](#callbacks)
  - [Defaults](#defaults)
  - [Message Format](#message-format)
  - [Results](#results)
- [Options](#options)
- [Transactions](#transactions)

## Distribution

We'll start with the big one;

In the v1.x line of Cachex, there was a notion of remote Cachex instances which have been removed in v2.x onwards. This is a design decision due to the limitations of supporting remote instances and the complexities involved, specifically with regards to discovery and eviction policies.

In order to migrate away from this, you should now implement a backing datastore such as Redis or Memcached as your master copy and make use of the Cachex fallback behaviour to replicate the data to your local nodes. To handle the removal of data from remote nodes, you should set a TTL on your data and it will periodically and flush automatically. This should support most cases that people were using the distributed nature of Cachex for, but with the main difference that the consistency is now guaranteed and will remain eventually consistent on the local nodes.

The decision to remove the remote interface does not come lightly; I have spent many weeks trying to conjure something which satisfies the desire of both speed and distribution and the sad truth is that it's quite simply hard to do well. The consistency issues which plague the land of distributed data are just not possible to handle whilst keeping Cachex as fast as it is (and at the end of the day, a cache is supposed to be fast). The final tipping point was the concept of building LRU style caches in a remote context; it's simply not possible to guarantee the consistency of your data without a huge performance hit (we're talking upwards of 1000x slower) due to Cachex operating in the realm of a microsecond.

Do not despair though; if you were totally set on using a native Elixir/Erlang datastore witout having to have something separate such as Redis, I'm planning on writing a separate library which is dedicated more to handling the distributed nature as opposed to the feature set that Cachex offers. At the end of the day, I see caching as a different use case to remote data replication - I believe remote Cachex was closer to a distributed state table, rather than a local mirror of data.

In addition, you can obviously keep on using Cachex `v1.x` as long as you need - it's still on Hex.pm and has a tag on the repo. I can't promise anything new will be added to that codebase, but for what it's worth I do intend to answer any issues reporting bugs on that branch, so file issues as you see fit - just make sure to flag that you're talking about `v1.x`.

## Fallbacks

The options and interface for fallback functions have changed a little bit in order to optimize their efficiency and just remove some bloat from the fallback flow.

In the v1.x branch of Cachex, there were two cache options related to fallbacks; `:default_fallback` and `:fallback_args`. This was a little clumsy looking, and so this has been unified in v2.x to only be a simple `:fallback` option. This can either be a function, or list of fallback options. Below are some examples:

```elixir
# fallback with no state
[ fallback: fn(key) -> do_fallback(key) end ]
[ fallback: [ action: fn(key) -> do_fallback(key) end ] ]

# fallback with a state
[
  fallback: [
    state: db_client,
    action: fn(key, client) ->
      retrieve_from_db(client, key)
    end
  ]
]

# provide a state but no default fallback
[ fallback: [ state: db_client ] ]
```

It should be noted that the `state` is passed in as a second argument in the case that the `state` provided is not `nil`. This is another change to previously where you would provide a list and have arbitrarily long arguments. This change was made as it's a more efficient way of calling a fallback and lessens the overhead involved.

## Hook Interface

Hooks have undergone a bit of tweaking in v2 simply because they were built back when I wasn't fully familiar with the `Gen*` models. The changes are easy to adopt and shouldn't take you much more than a few minutes to modify your codebase:

### Callbacks

The biggest change made to Hooks is that we have migrated from `GenEvent` to `GenServer`. This means that if you're implementing Hooks, you need to respect the return formats of the `GenServer` module rather than that of `GenEvent`. This only affects the `Gen*` callbacks, such as `handle_call/2` and `handle_info/2`, so if you haven't used them you're going to be fine in this respect.

The `handle_call/2` callback should become `handle_call/3`, with a new second parameter which is simply the context of the call (and you likely won't ever use). In addition, the return type now becomes `{ :reply, reply, new_state }` instead of `{ :ok, reply, new_state }` - so just a few characters to tweak there. The same applies for `handle_info/2` in that you need to change `{ :ok, new_state }` to `{ :noreply, new_state }`.

The reason the change was made is that your hooks now live in the Supervision tree alongside the cache, rather than under a `GenEvent` process. This allows shutdown to run more smoothly, and just generally lays out the tree much better. In addition, you now gain access to `handle_cast/2` from the `GenServer` module and it's a much more familiar interface to deal with as opposed to `GenEvent`, which is falling more and more out of use by most Elixir developers.

### Defaults

The only big change here is that the `:type` option of a hook previously defaulted to being a `:pre` hook. This has now changed to default to a `:post` hook.

The reasoning behind this is that post hooks are a more common use case - you typically don't want to react to the desire to do something, you want to react to something happening. It was also quite easy to become confused when trying to play with results and receiving nothing. This sucked, because it meant that an entirely different function would be called because of the arity changes when requesting results.

This is a very easy thing to update, and you can always make sure to specify `:type` on your Hooks in future to avoid relying on this default (I imagine most people have done that anyway, so good job!).

### Message Format

After talking to a couple of people on the Slack channels, it dawned on me that the current Hook message implementation is quite bad - in the sense that there's a performance hit, and it's awkward to use. The currently pattern behaves as a Tuple of action arguments, so `Cachex.get(:cache, "key", opts)` would forward as `{ :get, "key", opts }`.

At a glance it looks like there's nothing wrong with this, but it makes pattern matching difficult and there's clearly a Tuple construction to create that message. Going forward, it is now guaranteed that a message will be a two-element Tuple, with the action as a tag and a list of arguments - so the above would become `{ :get, [ "key", opts ]}`.

This change makes it super easy to pattern match on the action name (for example, the new LRW hook only activates on write actions), and gives you the guarantee that your message will always be the same form as opposed to having arbitrarily long Tuples (which is pretty much always the wrong thing to do).

### Results

The decision has been made to always provide results to a post hook, in order to keep the backing logic simple and remove some conditions. It's cheap to forward the results, so there's no real overhead to doing this. Previously the intent was to separate the concerns, but it just led to confusing message handling due to having to use both `handle_notify/2` and `handle_notify/3`. Going forward, you will only ever use `handle_notify/3` (because `handle_notify/2` has been removed). This means that results are also given to your `:pre` hooks, but they're **always** `nil` inside a pre hook and can just be ignored. You should note that if you were previously using `results: true` in your Hook, you shouldn't need to change anything. Examples below:

```elixir
# old format
def handle_notify(msg, state)

# new format
def handle_notify(msg, result, state)
```

Obviously because this is always enabled there's no need for an option, and so the `:results` option has been removed from the Hook struct - so you need to drop it from any Hook definitions you have.

## Options

There are a few minor tweaks to the options when starting a cache:

1. The first change is that the previously deprecated `:name` option has been removed. You should now use `start_link/3` or `start/3` and pass the cache name as the first argument. This is to remove some complexity with name validation (in that it's easier to pick out now without parsing options first).

2. The `:ttl_interval` could previously be disabled if set to `false`. This has changed as it's required to be numeric at this point for other reasons, so going forward you should pass `-1` if you wish to disable the interval.

3. This is a small change, but it bothered me often enough to make it. The `:default_fallback` option has been simply renamed to `:fallback`, as it's much easier to write and it's more consistent with the same option inside a `get/3` call (which is also `:fallback`). Long gone are the days in which you pass `:fallback` to a cache only to have it ignored.

## Transactions

As of Cachex v2.x, Mnesia has been removed in favour of direct ETS interation. As a result of this, there are several changes in the way transactions work.

The first change is down to optimizations of key locking, and requires that you now pass a list of keys to lock as your second parameter to a `transaction/3` call. This is part of the new locking implementation which allows for several optimizations by being explicit with your locks. This optimization provides roughly a 5x speedup, so it's much more efficient than previously. This is pretty easy to adopt:

```elixir
Cachex.transaction(:my_cache, [ "key1" ], fn(state) ->
  old_val = Cachex.get!("key1")
  new_val = do_something(old_val)
  Cachex.set!("key1", new_val)
end)
```

If you write to a key which has not been defined in the `keys` parameter, please be aware that it will not be locked and may be written by other processes during your transaction. It also goes without saying that nested transactions should only operate on a subset of keys in an outer transaction.

The second change is that there is no longer support for `abort/1` from within a transaction, meaning that all writes happen immediately even within your transaction. I don't believe this should be difficult to adopt, as I would imagine that `abort/1` is only used infrequently. It should not be hard to simply rework your transaction flow to exit as needed.

The final thing to note here is that transactions are all handled by a lock process, which means you should try to avoid causing a bottleneck in your transactions. For example, if you need to check list membership or create new Tuples, try do this outside your transaction first and simply pass it through - this will lessen the time spent in the transaction process and improve performance with transactions. This isn't always possible, but try to optimize like this when applicable.
