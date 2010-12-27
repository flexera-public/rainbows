# -*- encoding: binary -*-
# :stopdoc:
Rainbows.const_set(:CoolioThreadSpawn, Rainbows::RevThreadSpawn)
# :startdoc:

# A combination of the Coolio and ThreadSpawn models.  This allows Ruby
# Thread-based concurrency for application processing.  It DOES NOT
# expose a streamable "rack.input" for upload processing within the
# app.  DevFdResponse should be used with this class to proxy
# asynchronous responses.  All network I/O between the client and
# server are handled by the main thread and outside of the core
# application dispatch.
#
# Unlike ThreadSpawn, Cool.io makes this model highly suitable for
# slow clients and applications with medium-to-slow response times
# (I/O bound), but less suitable for sleepy applications.
#
# This concurrency model is designed for Ruby 1.9, and Ruby 1.8
# users are NOT advised to use this due to high CPU usage.
module Rainbows::CoolioThreadSpawn; end
