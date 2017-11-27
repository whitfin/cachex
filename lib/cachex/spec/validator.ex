defmodule Cachex.Spec.Validator do
  import Cachex.Spec

  def valid?(entry(touched: touched, ttl: ttl)),
    do: is_integer(touched) and (is_nil(ttl) or is_integer(ttl))

  def valid?(expiration(default: default, interval: interval, lazy: lazy)),
    do: (is_nil(default) or is_integer(default)) and
        (is_nil(interval) or is_integer(interval)) and
        is_boolean(lazy)

  def valid?(fallback(default: default)),
    do: is_function(default)

  def valid?(hooks(pre: pre, post: post)),
    do: is_list(pre) and is_list(post) and Enum.all?(pre ++ post, &match?(hook(), &1))

  def valid?(limit(size: size, policy: policy, reclaim: reclaim, options: options)) do
    with true <- (is_nil(size) or (is_number(size) and size > 0)),
         true <- is_atom(policy),
         true <- (is_number(reclaim) and reclaim > 0 and reclaim <= 1),
     do: Keyword.keyword?(options)
  end

  def valid?(hook(async: async, module: module, options: options, provide: provide, timeout: timeout, type: type)) do
    module.__info__(:module)
    with true <- (type == :pre or type == :post),
         true <- (is_nil(timeout) or is_integer(timeout)),
         true <- is_list(provide),
         true <- is_boolean(async),
     do: Keyword.keyword?(options)
  rescue
    _ -> false
  end
end
