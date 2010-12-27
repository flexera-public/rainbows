# -*- encoding: binary -*-
begin
  require 'coolio'
  Coolio::VERSION >= '1.0.0' or abort 'cool.io >= 1.0.0 is required'
rescue LoadError
  require 'rev'
  Rev::VERSION >= '0.3.0' or abort 'rev >= 0.3.0 is required'
end
require 'rev' if defined?(Coolio)

# Coolio is the new version of this, use that instead.
#
# Implements a basic single-threaded event model with
# {Rev}[http://rev.rubyforge.org/].  It is capable of handling
# thousands of simultaneous client connections, but with only a
# single-threaded app dispatch.  It is suited for slow clients and
# fast applications (applications that do not have slow network
# dependencies) or applications that use DevFdResponse for deferrable
# response bodies.  It does not require your Rack application to be
# thread-safe, reentrancy is only required for the DevFdResponse body
# generator.
#
# Compatibility: Whatever \Rev itself supports, currently Ruby
# 1.8/1.9.
#
# This model does not implement as streaming "rack.input" which
# allows the Rack application to process data as it arrives.  This
# means "rack.input" will be fully buffered in memory or to a
# temporary file before the application is entered.

module Rainbows::Rev
  # :stopdoc:
  # keep-alive timeout scoreboard
  KATO = {}

  # all connected clients
  CONN = {}

  if {}.respond_to?(:compare_by_identity)
    CONN.compare_by_identity
    KATO.compare_by_identity
  end

  autoload :Master, 'rainbows/rev/master'
  autoload :ThreadClient, 'rainbows/rev/thread_client'
  autoload :DeferredChunkResponse, 'rainbows/rev/deferred_chunk_response'
  # :startdoc:
end
# :enddoc:
require 'rainbows/rev/heartbeat'
require 'rainbows/rev/server'
require 'rainbows/rev/core'
require 'rainbows/rev/deferred_response'
require 'rainbows/rev/client'
Rainbows::Rev.__send__ :include, Rainbows::Rev::Core
