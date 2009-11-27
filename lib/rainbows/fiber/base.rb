# -*- encoding: binary -*-
require 'rainbows/fiber/io'

module Rainbows
  module Fiber

    # blocked readers (key: Rainbows::Fiber::IO object, value is irrelevant)
    RD = {}

    # blocked writers (key: Rainbows::Fiber::IO object, value is irrelevant)
    WR = {}

    # sleeping fibers go here (key: Fiber object, value: wakeup time)
    ZZ = {}

    # puts the current Fiber into uninterruptible sleep for at least
    # +seconds+.  Unlike Kernel#sleep, this it is not possible to sleep
    # indefinitely to be woken up (nobody wants that in a web server,
    # right?).
    def self.sleep(seconds)
      ZZ[::Fiber.current] = Time.now + seconds
      ::Fiber.yield
    end

    # base module used by FiberSpawn and FiberPool
    module Base
      include Rainbows::Base

      # the scheduler method that powers both FiberSpawn and FiberPool
      # concurrency models.  It times out idle clients and attempts to
      # schedules ones that were blocked on I/O.  At most it'll sleep
      # for one second (returned by the schedule_sleepers method) which
      # will cause it.
      def schedule(&block)
        ret = begin
          G.tick
          RD.keys.each { |c| c.f.resume } # attempt to time out idle clients
          t = schedule_sleepers
          Kernel.select(RD.keys.concat(LISTENERS), WR.keys, nil, t) or return
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF, TypeError
          LISTENERS.compact!
          raise
        end or return

        # active writers first, then _all_ readers for keepalive timeout
        ret[1].concat(RD.keys).each { |c| c.f.resume }

        # accept is an expensive syscall, filter out listeners we don't want
        (ret.first & LISTENERS).each(&block)
      end

      # wakes up any sleepers that need to be woken and
      # returns an interval to IO.select on
      def schedule_sleepers
        max = nil
        now = Time.now
        ZZ.delete_if { |fib, time|
          if now >= time
            fib.resume
            now = Time.now
          else
            max = time
            false
          end
        }
        max.nil? || max > (now + 1) ? 1 : max - now
      end

      def process_client(client)
        G.cur += 1
        io = client.to_io
        buf = client.read_timeout or return
        hp = HttpParser.new
        env = {}
        alive = true
        remote_addr = TCPSocket === io ? io.peeraddr.last : LOCALHOST

        begin # loop
          while ! hp.headers(env, buf)
            buf << (client.read_timeout or return)
          end

          env[RACK_INPUT] = 0 == hp.content_length ?
                    HttpRequest::NULL_IO : TeeInput.new(client, env, hp, buf)
          env[REMOTE_ADDR] = remote_addr
          response = APP.call(env.update(RACK_DEFAULTS))

          if 100 == response.first.to_i
            client.write(EXPECT_100_RESPONSE)
            env.delete(HTTP_EXPECT)
            response = APP.call(env)
          end

          alive = hp.keepalive? && G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
          HttpResponse.write(client, response, out)
        end while alive and hp.reset.nil? and env.clear
      rescue => e
        handle_error(io, e)
      ensure
        G.cur -= 1
        RD.delete(client)
        WR.delete(client)
        ZZ.delete(client.f)
        io.close unless io.closed?
      end

    end
  end
end