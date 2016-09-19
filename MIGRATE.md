# Migrating v1.x to v2.x

If anything is not covered in here, or there are any issues with anything written in here, please file an issue and I'll get it taken care of.

- [Distribution](#distribution)
- [Hook Interface](#hook-interface)
  - [Callbacks](#callbacks)
  - [Defaults](#defaults)
  - [Message Format](#message-format)
  - [Results](#results)
- [Options](#options)
- [Transactions](#transactions)

## Distribution

In the v1.x line of Cachex, there was a notion of remote Cachex instances which have been removed in v2.x onwards. This is a design decision due to the limitations of supporting remote instances and the complexities involved, specifically with regards to discovery and eviction policies.

As an alternative to remote Cachex instances, you should now use a remote datastore such as Redis as your master copy and use fallback functions inside Cachex to replicate this data locally. This should support almost all cases for which people required the distributed nature of Cachex. To migrate the behaviour of deletion on remote nodes, simply set a TTL on your data which pulls from Redis and it'll periodically sync automatically. This has the advantage of removing a lot of complexity from Cachex whilst still solving many common use cases.

If there are cases this doesn't solve, please file issues with a description of what you're trying to do and we can work together to design how to efficiently implement it inside Cachex. I'm not against reintroducing the idea of remote caches if there is an audience for them, as long as they're implemented in such a way that it doesn't limit local caches. There are several ideas in flux around how to make this happen but each needs a lot of thought and review, and so will only be revisited as needed. It may be that this turns into a new library totally based around being an Elixir distributed cache, rather than being forced into Cachex.

## Hook Interface

There have been a couple of tweaks to the interface behind hooks to make them more convenient to work with:

### Callbacks

The biggest change made to Hooks is that we have migrated from `GenEvent` to `GenServer`. This means that if you're implementing Hooks, you need to respect the return formats of the `GenServer` module rather than that of `GenEvent`. This only affects callbacks, such as `handle_call/2` and `handle_info/2`, so if you haven't used them you're going to be fine.

The `handle_call/2` callback should become `handle_call/3`, with a new second parameter which is simply the context of the call (and you likely won't ever use). In addition, the return type now becomes `{ :reply, reply, new_state }` instead of `{ :ok, reply, new_state }` - so just a few characters to tweak there. The same applies for `handle_info/2` in that you need to change `{ :ok, new_state }` to `{ :noreply, new_state }`.

The reason the change was made is that your hooks now live in the Supervision tree alongside the cache, rather than under a `GenEvent` process. This allows shutdown to run more smoothly, and just generally lays out the tree much better. In addition, you now gain access to `handle_cast/2` from the `GenServer` module and it's a much more familiar interface to deal with as opposed to `GenEvent`, which is falling out of use.

### Defaults

Firstly, Hooks will default to being of `type: :post`. This is because post hooks are the more common use case, and it was very easy to become confused when trying to deal with results and receiving nothing (because of the default to `:pre`). I feel that defaulting to `:post` going forward is more user-friendly. This is a very easy thing to update, and you should make sure to always specify `:type` on your Hooks in future to avoid relying on this default.

### Message Format

There has been a change in the message format used to talk to Hooks. Previously this was a Tuple of the action and arguments, e.g. `{ :get, "key", [] }`. Going forward, this will always be a two-element Tuple, with the action and a list of arguments, e.g. `{ :get, [ "key", [] ] }`. This change makes it easier to pattern match only on the action (something very common in hooks) and avoids arbitrarily long Tuples (which is almost always the wrong thing to do).

### Results

Results are now always provided in the call to a Hook, in order to keep the logic behind hook notifications simply and remove some messy conditions there. If you have a `:pre` hook, it will simply receive `nil` as the results.

The above means that the `:results` option in the Hook struct has been removed, and that `handle_notify/2` is no longer used. These two things are fairly easy to adapt to. For the `:results` option, simply drop it from any Hook definitions that you may have and you should be good to go. Adapting from `handle_notify/2` to `handle_notify/3` is also easy enough, it's as straightforward as adding a new parameter to the function as shown below. If you previously had `results: true`, then no change is needed.

```
def handle_notify(msg, state)
def handle_notify(msg, result, state)
```

## Options

There are a few option changes on a cache interface when starting one up in v2. The first is that passing the `:name` option in the list of options has been totally removed, rather than just being deprecated. You must now provide the cache name as the first parameter in `start_link/3`. Other changes include:

- `ttl_interval: false` should be replaced with `ttl_interval: -1`, as `false` is no longer recognised.
- `:default_fallback` has been renamed to `:fallback`, this should be used going forward.

## Transactions

There are a number of changes in Transactions due to the removal of Mnesia which occurred in Cachex v2. The first is that you must now define the keys you wish to lock in your transaction call as the second parameter. This is part of a new locking mechanism which optimizes the cache to run faster by forcing you to specify your locks (previously there was a table lock). This has the advantage of speeding up transactions by roughly 5x. This is fairly easy to adopt, you just pass any keys you write to in your transactions in a list as the second parameter:

```elixir
Cachex.transaction(:my_cache, [ "key1" ], fn(state) ->
  old_val = Cachex.get!("key1")
  new_val = do_something(old_val)
  Cachex.set!("key1", new_val)
end)
```

If you don't pass a key you write, it will not be protected by the locking Cachex works against and may be overwritten in the middle of a transaction. You should note that there is no longer an `abort/1` function for use inside a transaction. This is because your writes happen immediately and without a checkpoint, so there's no way to roll them back. You should therefore handle aborts in your logic rather than just bailing out - this is clearly possible as you have a consistent view of all the keys you need before any changes occur.
