defmodule Cachex.Memoize do
  @moduledoc """
  ## Cachex.Memoize

  Cachex.Memoize provides straightforward memoization macros using Cachex as a backend.

  ## How to memoize

  If you want to cache a function, `use Cachex.Memoize` on the module and change `def` to `defmemo` and specify a cache.
  IMPORTANT! If your cache is not started the function will run directly without Cachex. If this behaviour is not desirable You can provide a `fail` parameter.

  for example:

  ```elixir
  defmodule Example do
    def f(x) do
      Process.sleep(1000)
      x + 1
    end
  end
  ```

  this code changes to:

  ```elixir
  Cachex.start(:mycache) # Normally you would `start_link` Cachex in a supervisor.

  defmodule Example do
    use Cachex.Memoize
    defmemo f(x), cache: :mycache do
      Process.sleep(1000)
      x + 1
    end
  end
  ```

  If a function defined by `defmemo` raises an error, the result is not cached and one of waiting processes will call the function.

  ## Exclusive

  A caching function that is defined by `defmemo` is never called in parallel.

  ```elixir
  Cachex.start(:mycache)
  defmodule Calc do
  use Memoize
  defmemo calc(), cache: :mycache do
    Process.sleep(1000)
    IO.puts "called!"
  end
  end

  # call `Calc.calc/0` in parallel using many processes.
  for _ <- 1..10000 do
  Process.spawn(fn -> Calc.calc() end, [])
  end

  # but, actually `Calc.calc/0` is called only once.
  ```
  """

  defmacro __using__(_) do
    quote do
      import Cachex.Memoize, only: [defmemo: 1, defmemo: 2, defmemo: 3, defmemop: 1, defmemop: 2, defmemop: 3]
      @memoize_memodefs []
      @memoize_origdefined %{}
      @before_compile Cachex.Memoize
    end
  end

  @doc """
    Macro used to define a public memoized function.

    ## Options
    * `cache` # Mandatory

        </br>
        The cache to use for the memoization.

    * `ttl`

        </br>
        An expiration time to set for the provided key (time-to-live), overriding
        any default expirations set on a cache. This value should be in milliseconds.

    * `fail`

        </br>
        Override default behaviour to bypass cache when it is not available.
        Fail fast instead of allowing potentially expensive operations to be executed in parallel.
        Possible values are:
          * `false` (default) this means we bypass the cache when it is not available.
          * `true` this is the same as `{:value, {:error, :no_cache}}`. In other words the
             function will return `{:error, :no_cache}` when the cache is not available.
          * `{:value, term()}` function will return this value when the cache is missing.
          * `{:error, term()}` function will return this error when the cache is missing.
          * `{:throw, term()}` function will throw this value when the cache is missing.
          * `{:exit, term()}` function will exit with this value when the cache is missing.
          * `{:raise, term()}` function will raise with this value when the cache is missing.


    ## Example

        defmodule Example do
          use Cachex.Memoize
          defmemop f(x), cache: :mycache, ttl: 1_000, fail: true do
            Process.sleep(100)
            x + 1
          end
        end

  """
  defmacro defmemo(call, expr_or_opts \\ nil) do
    {opts, expr} = resolve_expr_or_opts(expr_or_opts)
    define(:def, call, opts, expr)
  end

  @doc """
    Macro used to define a private memoized function.

    ## Options
    * `cache` # Mandatory

        </br>
        The cache to use for the memoization.

    * `ttl`

        </br>
        An expiration time to set for the provided key (time-to-live), overriding
        any default expirations set on a cache. This value should be in milliseconds.

    * `fail`

        </br>
        Override default behaviour to bypass cache when it is not available.
        Fail fast instead of allowing potentially expensive operations to be executed in parallel.
        Possible values are:
          * `false` (default) this means we bypass the cache when it is not available.
          * `true` this is the same as `{:value, {:error, :no_cache}}`. In other words the
             function will return `{:error, :no_cache}` when the cache is not available.
          * `{:value, term()}` function will return this value when the cache is missing.
          * `{:error, term()}` function will return this error when the cache is missing.
          * `{:throw, term()}` function will throw this value when the cache is missing.
          * `{:exit, term()}` function will exit with this value when the cache is missing.
          * `{:raise, term()}` function will raise with this value when the cache is missing.


    ## Example

        defmodule Example do
          use Cachex.Memoize
          defmemo f(x), cache: :mycache, ttl: 1_000, fail: true do
            Process.sleep(100)
            x + 1
          end
        end

  """
  defmacro defmemop(call, expr_or_opts \\ nil) do
    {opts, expr} = resolve_expr_or_opts(expr_or_opts)
    define(:defp, call, opts, expr)
  end

  defmacro defmemo(call, opts, expr) do
    define(:def, call, opts, expr)
  end

  defmacro defmemop(call, opts, expr) do
    define(:defp, call, opts, expr)
  end

  defp resolve_expr_or_opts(expr_or_opts) do
    cond do
      expr_or_opts == nil ->
        {[], nil}

      # expr_or_opts is expr
      Keyword.has_key?(expr_or_opts, :do) ->
        {[], expr_or_opts}

      # expr_or_opts is opts
      true ->
        {expr_or_opts, nil}
    end
  end

  defp define(method, call, _opts, nil) do
    # declare function
    quote do
      case unquote(method) do
        :def -> def unquote(call)
        :defp -> defp unquote(call)
      end
    end
  end

  defp define(method, call, opts, expr) do
    register_memodef =
      case call do
        {:when, meta, [{origname, exprmeta, args}, right]} ->
          quote bind_quoted: [
                  expr: Macro.escape(expr, unquote: true),
                  origname: Macro.escape(origname, unquote: true),
                  exprmeta: Macro.escape(exprmeta, unquote: true),
                  args: Macro.escape(args, unquote: true),
                  meta: Macro.escape(meta, unquote: true),
                  right: Macro.escape(right, unquote: true)
                ] do
            require Cachex.Memoize

            fun = {:when, meta, [{Cachex.Memoize.__memoname__(origname), exprmeta, args}, right]}
            @memoize_memodefs [{fun, expr} | @memoize_memodefs]
          end

        {origname, exprmeta, args} ->
          quote bind_quoted: [
                  expr: Macro.escape(expr, unquote: true),
                  origname: Macro.escape(origname, unquote: true),
                  exprmeta: Macro.escape(exprmeta, unquote: true),
                  args: Macro.escape(args, unquote: true)
                ] do
            require Cachex.Memoize

            fun = {Cachex.Memoize.__memoname__(origname), exprmeta, args}
            @memoize_memodefs [{fun, expr} | @memoize_memodefs]
          end
      end

    fun =
      case call do
        {:when, _, [fun, _]} -> fun
        fun -> fun
      end

    deffun =
      quote bind_quoted: [
              fun: Macro.escape(fun, unquote: true),
              method: Macro.escape(method, unquote: true),
              opts: Macro.escape(opts, unquote: true)
            ] do
        {origname, from, to} = Cachex.Memoize.__expand_default_args__(fun)
        memoname = Cachex.Memoize.__memoname__(origname)

        for n <- from..to do
          args = Cachex.Memoize.__make_args__(n)

          unless Map.has_key?(@memoize_origdefined, {origname, n}) do
            @memoize_origdefined Map.put(@memoize_origdefined, {origname, n}, true)
            location = __ENV__ |> Macro.Env.location()
            file = location |> Keyword.get(:file)
            line = location |> Keyword.get(:line)
            "Elixir." <> module = __ENV__ |> Map.get(:module) |> Atom.to_string()
            unless opts |> Keyword.has_key?(:cache) do
              raise "#{file}:#{line} #{module}.#{origname} missing mandatory parameter 'cache' (see Cachex.Memoize for documentation)"
            end

            if opts |> Keyword.has_key?(:fail) do
              fail = opts |> Keyword.get(:fail, false)
              case fail do
                false -> :ok
                true -> :ok
                {:value, _val} -> :ok
                {:throw, _val} -> :ok
                {:error, _val} -> :ok
                {:raise, _val} -> :ok
                {:exit,  _val} -> :ok
                _ -> raise "#{file}:#{line} #{module}.#{origname} invalid 'fail' parameter with value '#{inspect fail}' (see Cachex.Memoize for documentation)"
              end
            end
            cache = opts |> Keyword.get(:cache)
            fail = opts |> Keyword.get(:fail, false)
            #IMPORTANT: If you update this code remember that there is two copies of it. One for `def` and `defp`.
            #           Also if you find a way to parameterize `method` please do so I was not able to do it.
            #           See https://elixirforum.com/t/metaprogramming-code-reuse/20621/9 for details.
            case method do
              :def ->
                def unquote(origname)(unquote_splicing(args)) do
                  key = {__MODULE__, unquote(origname), [unquote_splicing(args)]}
                  memo_opts = unquote(opts)
                  cache = unquote(cache)
                  fail = unquote(fail)
                  case Cachex.transaction(cache, [key], fn cache ->
                    case Cachex.get(cache, key) do
                      {:ok, nil} ->
                        result = try do
                          {:success, unquote(memoname)(unquote_splicing(args))}
                        catch
                          :error, %RuntimeError{message: payload} ->
                            {:raise, payload}
                          :error, payload ->
                            {:error, payload}
                          :throw, payload ->
                            {:throw, payload}
                          :exit, payload ->
                            {:exit, payload}
                        end
                        put_opts = if Keyword.has_key?(memo_opts, :ttl) do
                          [ttl: memo_opts |> Keyword.get(:ttl)]
                        else
                          []
                        end
                        {:ok, true} = Cachex.put(cache, key, result, put_opts)
                        result
                      {:ok, result} ->
                        result
                      {:error, :no_cache} ->
                        case fail do
                          false -> unquote(memoname)(unquote_splicing(args))
                          true -> {:error, :no_cache}
                          {:value, val} -> val
                          {:throw, val} -> Kernel.throw(val)
                          {:error, val} -> :erlang.error(val)
                          {:raise, val} -> Kernel.raise(val)
                          {:exit,  val} -> Kernel.exit(val)
                        end
                    end
                  end) do
                    {:ok, result} ->
                      case result do
                        {:success, result} -> result
                        {:raise, payload}  -> Kernel.raise(payload)
                        {:error, payload}  -> :erlang.error(payload)
                        {:throw, payload}  -> Kernel.throw(payload)
                        {:exit,  payload}  -> Kernel.exit(payload)
                      end
                    {:error, :no_cache} ->
                      case fail do
                        false -> unquote(memoname)(unquote_splicing(args))
                        true -> {:error, :no_cache}
                        {:value, val} -> val
                        {:throw, val} -> Kernel.throw(val)
                        {:error, val} -> :erlang.error(val)
                        {:raise, val} -> Kernel.raise(val)
                        {:exit,  val} -> Kernel.exit(val)
                      end
                  end
                end
              :defp ->
                defp unquote(origname)(unquote_splicing(args)) do
                  key = {__MODULE__, unquote(origname), [unquote_splicing(args)]}
                  memo_opts = unquote(opts)
                  cache = unquote(cache)
                  fail = unquote(fail)
                  case Cachex.transaction(cache, [key], fn cache ->
                    case Cachex.get(cache, key) do
                      {:ok, nil} ->
                        result = try do
                          {:success, unquote(memoname)(unquote_splicing(args))}
                        catch
                          :error, %RuntimeError{message: payload} ->
                            {:raise, payload}
                          :error, payload ->
                            {:error, payload}
                          :throw, payload ->
                            {:throw, payload}
                          :exit, payload ->
                            {:exit, payload}
                        end
                        put_opts = if Keyword.has_key?(memo_opts, :ttl) do
                          [ttl: memo_opts |> Keyword.get(:ttl)]
                        else
                          []
                        end
                        {:ok, true} = Cachex.put(cache, key, result, put_opts)
                        result
                      {:ok, result} ->
                        result
                      {:error, :no_cache} ->
                        case fail do
                          false -> unquote(memoname)(unquote_splicing(args))
                          true -> {:error, :no_cache}
                          {:value, val} -> val
                          {:throw, val} -> Kernel.throw(val)
                          {:error, val} -> :erlang.error(val)
                          {:raise, val} -> Kernel.raise(val)
                          {:exit,  val} -> Kernel.exit(val)
                        end
                    end
                  end) do
                    {:ok, result} ->
                      case result do
                        {:success, result} -> result
                        {:raise, payload}  -> Kernel.raise(payload)
                        {:error, payload}  -> :erlang.error(payload)
                        {:throw, payload}  -> Kernel.throw(payload)
                        {:exit,  payload}   -> Kernel.exit(payload)
                      end
                    {:error, :no_cache} ->
                      case fail do
                        false -> unquote(memoname)(unquote_splicing(args))
                        true -> {:error, :no_cache}
                        {:value, val} -> val
                        {:throw, val} -> Kernel.throw(val)
                        {:error, val} -> :erlang.error(val)
                        {:raise, val} -> Kernel.raise(val)
                        {:exit,  val} -> Kernel.exit(val)
                      end
                  end
                end
            end
          end
        end
      end

    [register_memodef, deffun]
  end


  # {:foo, 1, 3} == __expand_default_args__(quote(do: foo(x, y \\ 10, z \\ 20)))
  def __expand_default_args__(fun) do
    {name, args} = Macro.decompose_call(fun)

    is_default_arg = fn
      {:\\, _, _} -> true
      _ -> false
    end

    min_args = Enum.reject(args, is_default_arg)
    {name, length(min_args), length(args)}
  end

  # [] == __make_args__(0)
  # [{:t1, [], Elixir}, {:t2, [], Elixir}] == __make_args__(2)
  def __make_args__(0) do
    []
  end

  def __make_args__(n) do
    for v <- 1..n do
      {:"t#{v}", [], Elixir}
    end
  end

  def __memoname__(origname), do: :"__#{origname}_cachex_memoize"

  defmacro __before_compile__(_) do
    quote do
      @memoize_memodefs
      |> Enum.reverse()
      |> Enum.map(fn {memocall, expr} ->
        Code.eval_quoted({:defp, [], [memocall, expr]}, [], __ENV__)
      end)
    end
  end


end
