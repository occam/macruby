require 'test/unit'
require 'timeout'

class TestSignal < Test::Unit::TestCase
  def have_fork?
    begin
      Process.fork {}
      return true
    rescue NotImplementedError
      return false
    end
  end

  def test_signal
    return unless Process.respond_to?(:kill)
    begin
      x = 0
      oldtrap = Signal.trap(:INT) {|sig| x = 2 }
      Process.kill :INT, Process.pid
      sleep 0.1
      assert_equal 2, x

      Signal.trap(:INT) { raise "Interrupt" }
      ex = assert_raises(RuntimeError) {
        Process.kill :INT, Process.pid
        sleep 0.1
      }
      assert_kind_of Exception, ex
      assert_match(/Interrupt/, ex.message)
    ensure
      Signal.trap :INT, oldtrap if oldtrap
    end
  end

  def test_exit_action
    return unless have_fork?	# snip this test
    begin
      r, w = IO.pipe
      r0, w0 = IO.pipe
      pid = Process.fork {
        Signal.trap(:USR1, "EXIT")
        w0.close
        w.syswrite("a")
        Thread.start { Thread.pass }
        r0.sysread(4096)
      }
      r.sysread(1)
      sleep 0.1
      assert_nothing_raised("[ruby-dev:26128]") {
        Process.kill(:USR1, pid)
        begin
          Timeout.timeout(3) {
            Process.waitpid pid
          }
        rescue Timeout::Error
          Process.kill(:TERM, pid)
          raise
        end
      }
    ensure
      r.close
      w.close
      r0.close
      w0.close
    end
  end

  def test_invalid_signal_name
    return unless Process.respond_to?(:kill)

    assert_raise(ArgumentError) { Process.kill(:XXXXXXXXXX, $$) }
  end

  def test_signal_exception
    assert_raise(ArgumentError) { SignalException.new }
    assert_raise(ArgumentError) { SignalException.new(-1) }
    assert_raise(ArgumentError) { SignalException.new(:XXXXXXXXXX) }
    Signal.list.each do |signm, signo|
      next if signm == "EXIT"
      assert_equal(SignalException.new(signm).signo, signo)
      assert_equal(SignalException.new(signm.to_sym).signo, signo)
      assert_equal(SignalException.new(signo).signo, signo)
    end
  end

  def test_interrupt
    assert_raise(Interrupt) { raise Interrupt.new }
  end

  def test_signal2
    return unless Process.respond_to?(:kill)
    begin
      x = false
      oldtrap = Signal.trap(:INT) {|sig| x = true }
      GC.start

      assert_raise(ArgumentError) { Process.kill }

      Timeout.timeout(10) do
        x = false
        Process.kill(SignalException.new(:INT).signo, $$)
        nil until x

        x = false
        Process.kill("INT", $$)
        nil until x

        x = false
        Process.kill("SIGINT", $$)
        nil until x

        x = false
        o = Object.new
        def o.to_str; "SIGINT"; end
        Process.kill(o, $$)
        nil until x
      end

      assert_raise(ArgumentError) { Process.kill(Object.new, $$) }

    ensure
      Signal.trap(:INT, oldtrap) if oldtrap
    end
  end

  def test_trap
    return unless Process.respond_to?(:kill)
    begin
      oldtrap = Signal.trap(:INT) {|sig| }

      assert_raise(ArgumentError) { Signal.trap }

      assert_raise(SecurityError) do
        s = proc {}.taint
        Signal.trap(:INT, s)
      end

      # FIXME!
      Signal.trap(:INT, nil)
      Signal.trap(:INT, "")
      Signal.trap(:INT, "SIG_IGN")
      Signal.trap(:INT, "IGNORE")

      Signal.trap(:INT, "SIG_DFL")
      Signal.trap(:INT, "SYSTEM_DEFAULT")

      Signal.trap(:INT, "EXIT")

      assert_raise(ArgumentError) { Signal.trap(:INT, "xxxxxx") }
      assert_raise(ArgumentError) { Signal.trap(:INT, "xxxx") }

      Signal.trap(SignalException.new(:INT).signo, "SIG_DFL")

      assert_raise(ArgumentError) { Signal.trap(-1, "xxxx") }

      o = Object.new
      def o.to_str; "SIGINT"; end
      Signal.trap(o, "SIG_DFL")

      assert_raise(ArgumentError) { Signal.trap("XXXXXXXXXX", "SIG_DFL") }

    ensure
      Signal.trap(:INT, oldtrap) if oldtrap
    end
  end
end
