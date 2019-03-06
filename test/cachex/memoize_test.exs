defmodule Cachex.MemoizeTest do
  use CachexCase

  test "memoization simple" do
    {:ok, pid} = Cachex.start(:c1)

    defmodule M1 do
      use Cachex.Memoize
      defmemo ref(), cache: :c1 do
        make_ref()
      end
    end

    a = M1.ref()
    b = M1.ref()

    assert(a === b)
    Process.exit(pid, :normal)
  end

  test "memoization with ttl" do
    {:ok, pid} = Cachex.start(:c2)
    defmodule M2 do
      use Cachex.Memoize
      defmemo ref(), cache: :c2, ttl: 100 do
        make_ref()
      end
    end

    a = M2.ref()
    Process.sleep(150)
    b = M2.ref()
    c = M2.ref()

    assert(a !== b)
    assert(b === c)
    Process.exit(pid, :normal)
  end

  test "memoization is fast" do
    {:ok, pid} = Cachex.start(:c3)
    defmodule M3 do
      use Cachex.Memoize
      defmemo ref(), cache: :c3 do
        make_ref()
      end
    end
    assert(fn ->
        length(for _ <- 1..50_000 do
          M3.ref()
        end)
      end |> :timer.tc() |> elem(0) |> Kernel./(1_000) < 5_000)
    Process.exit(pid, :normal)
  end


  test "memoization with ttl is fast" do
    {:ok, pid} = Cachex.start(:c4)
    defmodule M4 do
      use Cachex.Memoize
      defmemo ref(), cache: :c4, ttl: 100 do
        make_ref()
      end
    end
    assert(fn ->
      length(for _ <- 1..50_000 do
        M4.ref()
      end)
    end |> :timer.tc() |> elem(0) |> Kernel./(1_000) < 5_000)
    Process.exit(pid, :normal)
  end

  test "memoization of throw" do
    {:ok, pid} = Cachex.start(:c5)
    defmodule M5 do
      use Cachex.Memoize
      defmemo one(), cache: :c5 do
        throw 1
      end
    end

    assert catch_throw(M5.one()) == 1
    assert catch_throw(M5.one()) == 1
    Process.exit(pid, :normal)
  end

  test "memoization of exit" do
    {:ok, pid} = Cachex.start(:c6)
    defmodule M6 do
      use Cachex.Memoize
      defmemo one(), cache: :c6 do
        exit 1
      end
    end

    assert catch_exit(M6.one()) == 1
    assert catch_exit(M6.one()) == 1
    Process.exit(pid, :normal)
  end

  test "memoization of error" do
    {:ok, pid} = Cachex.start(:c7)
    defmodule M7 do
      use Cachex.Memoize
      defmemo one(), cache: :c7 do
        :erlang.error 1
      end
    end

    assert catch_error(M7.one()) == 1
    assert catch_error(M7.one()) == 1
    Process.exit(pid, :normal)
  end

  test "memoization of raise" do
    {:ok, pid} = Cachex.start(:c8)
    defmodule M8 do
      use Cachex.Memoize
      defmemo one(), cache: :c8 do
        raise "one"
      end
    end

    assert_raise(RuntimeError, "one", &M8.one/0)
    Process.exit(pid, :normal)
  end

  test "memoization private" do
    {:ok, pid} = Cachex.start(:c9)

    defmodule M9 do
      use Cachex.Memoize
      defmemop ref(), cache: :c9 do
        make_ref()
      end

      def do_ref() do
        ref()
      end
    end

    a = M9.do_ref()
    b = M9.do_ref()

    assert(a === b)
    Process.exit(pid, :normal)
  end

  test "memoization with when and multiple parameters" do
    {:ok, pid} = Cachex.start(:c10)

    defmodule M10 do
      use Cachex.Memoize
      defmemo ref(x, y) when x > 1 and y < 1, cache: :c10  do
        make_ref()
      end
    end

    a = M10.ref(2, 0)
    b = M10.ref(2, 0)

    assert(a === b)
    Process.exit(pid, :normal)
  end

  test "memoization fails without mandatory cache parameter" do
    assert_raise(RuntimeError, fn ->
      defmodule M11 do
        use Cachex.Memoize
        defmemo ref() do
          make_ref()
        end
      end
    end)
  end

  test "memoization fails without mandatory cache parameter private" do
    assert_raise(RuntimeError, fn ->
      defmodule M12 do
        use Cachex.Memoize
        defmemop ref() do
          make_ref()
        end
      end
    end)
  end

  test "memoization fail false cache missing" do
    defmodule M13 do
      use Cachex.Memoize
      defmemo ref(), cache: :c13, fail: false, ttl: 1000 do
        make_ref()
      end
    end

    a = M13.ref()
    b = M13.ref()

    assert(a !== b)
  end

  test "memoization fail false cache present" do
    {:ok, pid} = Cachex.start(:c14)
    defmodule M14 do
      use Cachex.Memoize
      defmemo ref(), cache: :c14, fail: false, ttl: 1000 do
        make_ref()
      end
    end

    a = M14.ref()
    b = M14.ref()

    assert(a === b)
    Process.exit(pid, :normal)
  end

  test "memoization fail true cache missing" do
    defmodule M15 do
      use Cachex.Memoize
      defmemo ref(), cache: :c15, fail: true, ttl: 1000 do
        make_ref()
      end
    end

    assert(M15.ref() === {:error, :no_cache})
  end

  test "memoization fail value cache missing" do
    defmodule M16 do
      use Cachex.Memoize
      defmemo ref(), cache: :c16, fail: {:value, :nope}, ttl: 1000 do
        make_ref()
      end
    end

    assert(M16.ref() === :nope)
  end

  test "memoization invalid fail value cache missing crashes at compile time" do
    assert_raise(RuntimeError, fn ->
      defmodule M17 do
        use Cachex.Memoize
        defmemo ref(), cache: :c17, fail: :nope, ttl: 1000 do
          make_ref()
        end
      end
    end)
  end
end