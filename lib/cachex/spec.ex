defmodule Cachex.Spec do
  @moduledoc """
  Specification definitions based around records and utilities.

  This serves as the "parent" header file for Cachex, where all records
  and macros are located. It's designed as a single inclusion file which
  provides everything you might need to implement features in Cachex, and
  indeed when interacting with Cachex.

  Most macros in here should be treated as reserved for internal use only,
  but those based around records can be freely used by consumers of Cachex.
  """
  import Record

  #############
  # Constants #
  #############

  # a list of accepted service suffixes for a cache instance
  @services [:courier, :eternal, :janitor, :locksmith, :stats, :steward]

  #############
  # Typespecs #
  #############

  # Record specification for a cache instance
  @type cache ::
          record(:cache,
            name: atom,
            commands: map,
            compressed: boolean,
            expiration: expiration,
            fallback: fallback,
            hooks: hooks,
            limit: limit,
            nodes: [atom],
            ordered: boolean,
            transactional: boolean,
            warmers: [warmer]
          )

  # Record specification for a command instance
  @type command ::
          record(:command,
            type: :read | :write,
            execute: (any -> any | {any, any})
          )

  # Record specification for a cache entry
  @type entry ::
          record(:entry,
            key: any,
            touched: number,
            ttl: number,
            value: any
          )

  # Helper type for entry types
  @type entries :: entry | [entry]

  # Record specification for a cache expiration
  @type expiration ::
          record(:expiration,
            default: non_neg_integer,
            interval: non_neg_integer | nil,
            lazy: boolean
          )

  # Record specification for a cache fallback
  @type fallback ::
          record(:fallback,
            default: (any -> any) | (any, any -> any),
            state: any
          )

  # Record specification for a cache hook
  @type hook ::
          record(:hook,
            module: atom,
            state: any,
            name: GenServer.server()
          )

  # Record specification for multiple cache hooks
  @type hooks ::
          record(:hooks,
            pre: [hook],
            post: [hook]
          )

  # Record specification for a cache limit
  @type limit ::
          record(:limit,
            size: integer,
            policy: atom,
            reclaim: number,
            options: Keyword.t()
          )

  # Record specification for a cache warmer
  @type warmer ::
          record(:warmer,
            module: atom,
            state: any,
            async: boolean
          )

  ###########
  # Records #
  ###########

  @doc """
  Creates a cache record from the provided values.

  A cache record is used to represent the internal state of a cache, and is used
  when executing calls. Most values in here will be other records defined in the
  main specification, and as such please see their documentation for further info.
  """
  defrecord :cache,
    name: nil,
    commands: %{},
    compressed: false,
    expiration: nil,
    fallback: nil,
    hooks: nil,
    limit: nil,
    nodes: [],
    ordered: false,
    transactional: false,
    warmers: []

  @doc """
  Creates a command record from the provided values.

  A command is a custom action which can be executed against a cache instance. They
  consist of a type (`:read`/`:write`) and an execution function. The type determines
  what form the execution should take.

  In the case of a `:read` type, an execution function is a simple (any -> any) form,
  which will return the returned value directly to the caller. In the case of a `:write`
  type, an execution should be (any -> { any, any }) where the value in the left side
  of the returned Tuple will be returned to the caller, and the right side will be set
  inside the backing cache table.
  """
  defrecord :command,
    type: nil,
    execute: nil

  @doc """
  Creates an entry record from the provided values.

  An entry record represents a single entry in a cache table.

  Each entry has a key/value, along with a touch time and ttl. These records should never
  be used outside of the Cachex codebase other than when debugging, as they can change
  at any time and should be regarded as internal only.
  """
  defrecord :entry,
    key: nil,
    touched: nil,
    ttl: nil,
    value: nil

  @doc """
  Creates an expiration record from the provided values.

  An expiration record contains properties defining expiration policies for a cache.

  A default value can be provided which will then be added as a default TTL to all keys
  which do not have one set explicitly. This must be a positive millisecond integer.

  The interval being controlled here is the Janitor service schedule; it controls how
  often the purge runs in the background of your application to remove expired records.
  This can be disabled completely by setting the value to nil. This is also a millisecond
  integer.

  The lazy value determines whether or not records can be lazily removed on read. Since
  this is an expected behaviour it's enabled by default, but there are cases where you
  might wish to disable it (such as when consistency isn't that big an issue).
  """
  defrecord :expiration,
    default: nil,
    interval: 3000,
    lazy: true

  @doc """
  Creates a fallback record from the provided values.

  A fallback can consist of a nillable state to provide to a fallback definition when
  requested (via a fallback with an arity of 2). If a default action is provided, it
  should be a function of arity 1 or 2, depending on if it requires the state or not.
  """
  defrecord :fallback,
    default: nil,
    state: nil

  @doc """
  Creates a hook record from the provided values.

  Hook records contain the properties needed to start up a hook against a cache instance.
  There are several components in a hook record:

    * arguments to pass through to the hook init/1 callback.
    * a flag to set whether or not a hook should fire asynchronously.
    * the module name backing the hook, implementing the hook behaviour.
    * options to pass to the hook server instance (allowing for names, etc).
    * provisions to pass through to the hook provisioning callback.
    * a PID reference to a potentially running hook instance (optional).
    * the timeout to wait for a response when firing synchronous hooks.
    * the type of the hook (whether to fire before/after a request).

  These values are mainly provided by the user, and this record might actually be replaced
  in future with just a behaviour and a set of macros (as this record is very noisy now).
  """
  defrecord :hook,
    module: nil,
    state: nil,
    name: nil

  @doc """
  Creates a hooks collection record from the provided values.

  Hooks records are just a pre-sorted collection of hook records, grouped by their
  type so that notifications internally do not have to iterate and group manually.
  """
  defrecord :hooks,
    pre: [],
    post: []

  @doc """
  Creates a limit record from the provided values.

  A limit record represents size bounds on a cache, and the way size should be reclaimed.

  A limit should have a valid integer as the maximum cache size, which is used to determine
  when to cull records. By default, an LRW style policy will be applied to remove old records
  but this can also be customized using the policy value. The amount of space to reclaim at
  once can be provided using the reclaim option.

  You can also specify options to pass through to the policy server, in order to customize
  policy behaviour.
  """
  defrecord :limit,
    size: nil,
    policy: Cachex.Policy.LRW,
    reclaim: 0.1,
    options: []

  @doc """
  Creates a warmer record from the provided values.

  A warmer record represents cache warmer processes to be run to populate keys.

  A warmer should have a valid module provided, which correctly implements the behaviour
  associated with `Cachex.Warmer`. A state can also be provided, which will be passed
  to the execution callback of the provided module (which defaults to `nil`). An async
  flag determines if initial warmup will run asynchronously cache startup.
  """
  defrecord :warmer,
    module: nil,
    state: nil,
    async: false

  ###############
  # Record Docs #
  ###############

  @doc """
  Updates a cache record from the provided values.
  """
  @spec cache(cache, Keyword.t()) :: cache
  defmacro cache(record, args)

  @doc """
  Updates a command record from the provided values.
  """
  @spec command(command, Keyword.t()) :: command
  defmacro command(record, args)

  @doc """
  Updates an entry record from the provided values.
  """
  @spec entry(entry, Keyword.t()) :: entry
  defmacro entry(record, args)

  @doc """
  Updates an expiration record from the provided values.
  """
  @spec expiration(expiration, Keyword.t()) :: expiration
  defmacro expiration(record, args)

  @doc """
  Updates a fallback record from the provided values.
  """
  @spec fallback(fallback, Keyword.t()) :: fallback
  defmacro fallback(record, args)

  @doc """
  Updates a hook record from the provided values.
  """
  @spec hook(hook, Keyword.t()) :: hook
  defmacro hook(record, args)

  @doc """
  Updates a hooks record from the provided values.
  """
  @spec hooks(hooks, Keyword.t()) :: hooks
  defmacro hooks(record, args)

  @doc """
  Updates a limit record from the provided values.
  """
  @spec limit(limit, Keyword.t()) :: limit
  defmacro limit(record, args)

  @doc """
  Updates a warmer record from the provided values.
  """
  @spec warmer(warmer, Keyword.t()) :: warmer
  defmacro warmer(record, args)

  #############
  # Constants #
  #############

  @doc """
  Inserts constant values by a provided key.

  Constants are meant to only be used internally as they may change without
  warning, but they are exposed as part of the spec interface all the same.

  Constant blocks can use other constants in their definitions (as it's all
  just macros under the hood, and happens at compile time).
  """
  @spec const(atom) :: any
  defmacro const(key)

  # Constant to only run locally.
  defmacro const(:local),
    do: quote(do: [local: true])

  # Constant to disable hook notifications.
  defmacro const(:notify_false),
    do: quote(do: [notify: false])

  # Constant to override purge calls
  defmacro const(:purge_override_call),
    do: quote(do: {:purge, [[]]})

  # Constant to override purge results
  defmacro const(:purge_override_result),
    do: quote(do: {:ok, 1})

  # Constant to override purge calls
  defmacro const(:purge_override),
    do:
      quote(
        do: [
          via: const(:purge_override_call),
          hook_result: const(:purge_override_result)
        ]
      )

  # Constant to define cache table options
  defmacro const(:table_options),
    do:
      quote(
        do: [
          keypos: 2,
          read_concurrency: true,
          write_concurrency: true
        ]
      )

  ####################
  # Entry Generation #
  ####################

  @doc """
  Retrieves the ETS index for an entry field.
  """
  @spec entry_idx(atom) :: integer
  defmacro entry_idx(key),
    do: quote(do: entry(unquote(key)) + 1)

  @doc """
  Generates an ETS modification Tuple for entry field/value pairs.

  This will convert the entry field name to the ETS index under the
  hood, and return it inside a Tuple with the provided value.
  """
  @spec entry_mod({atom, any}) :: {integer, any}
  defmacro entry_mod({key, val}),
    do: quote(do: {entry_idx(unquote(key)), unquote(val)})

  defmacro entry_mod(updates) when is_list(updates),
    do:
      for(
        pair <- updates,
        do: quote(do: entry_mod(unquote(pair)))
      )

  @doc """
  Generates a list of ETS modification Tuples with an updated touch time.

  This will pass the arguments through and behave exactly as `entry_mod/1`
  except that it will automatically update the `:touched` field in the entry
  to the current time.
  """
  @spec entry_mod_now([{atom, any}]) :: [{integer, any}]
  defmacro entry_mod_now(pairs \\ []),
    do: quote(do: entry_mod(unquote([touched: quote(do: now())] ++ pairs)))

  @doc """
  Creates an entry record with an updated touch time.

  This delegates through to `entry/1`, but ensures that the `:touched` field is
  set to the current time as a millisecond timestamp.
  """
  @spec entry_now([{atom, any}]) :: [{integer, any}]
  defmacro entry_now(pairs \\ []),
    do: quote(do: entry(unquote([touched: quote(do: now())] ++ pairs)))

  ############
  # Services #
  ############

  @doc """
  Generates a service call for a cache.

  This will generate the service name for the provided cache and call
  the service with the provided message. The timeout for these service
  calls is `:infinity` as they're all able to block the caller.
  """
  @spec service_call(cache, atom, any) :: any
  defmacro service_call(cache, service, message) when service in @services do
    quote do
      cache(name: name) = unquote(cache)

      name
      |> name(unquote(service))
      |> GenServer.call(unquote(message), :infinity)
    end
  end

  #############
  # Utilities #
  #############

  @doc """
  Determines if a value is a negative integer.
  """
  @spec is_negative_integer(integer) :: boolean
  defmacro is_negative_integer(integer),
    do: quote(do: is_integer(unquote(integer)) and unquote(integer) < 0)

  @doc """
  Determines if a value is a positive integer.
  """
  @spec is_positive_integer(integer) :: boolean
  defmacro is_positive_integer(integer),
    do: quote(do: is_integer(unquote(integer)) and unquote(integer) > 0)

  @doc """
  Generates a named atom for a cache, using the provided service.

  The list of services is narrowly defined to avoid bloating the atom table as
  it's not garbage collected. This macro is only used when naming services.
  """
  @spec name(atom | binary, atom) :: atom
  defmacro name(name, service) when service in @services,
    do: quote(do: :"#{unquote(name)}_#{unquote(service)}")

  @doc """
  Retrieves the current system time in milliseconds.
  """
  @spec now :: integer
  defmacro now,
    do: quote(do: :os.system_time(1000))

  @doc """
  Checks if a nillable value satisfies a provided condition.
  """
  @spec nillable?(any, (any -> boolean)) :: boolean
  defmacro nillable?(nillable, condition),
    do:
      quote(
        do:
          is_nil(unquote(nillable)) or
            apply(unquote(condition), [unquote(nillable)])
      )

  @doc """
  Adds a :via delegation to a Keyword List.
  """
  @spec via(atom, Keyword.t()) :: Keyword.t()
  defmacro via(action, options),
    do: quote(do: [{:via, unquote(action)} | unquote(options)])

  @doc """
  Retrieves the currently handled stacktrace.
  """
  @spec stack_compat :: any
  defmacro stack_compat() do
    if Version.match?(System.version(), ">= 1.7.0") do
      quote(do: __STACKTRACE__)
    else
      quote(do: System.stacktrace())
    end
  end

  @doc """
  Wraps a value inside a tagged Tuple using the provided tag.
  """
  @spec wrap(any, atom) :: {atom, any}
  defmacro wrap(value, tag) when is_atom(tag),
    do: quote(do: {unquote(tag), unquote(value)})
end
