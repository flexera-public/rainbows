# -*- encoding: binary -*-
# :enddoc:
# non-portable body response stuff goes here
#
# The sendfile 1.0.0 RubyGem includes IO#sendfile and
# IO#sendfile_nonblock.   Previous versions of "sendfile" didn't have
# IO#sendfile_nonblock, and IO#sendfile in previous versions could
# block other threads under 1.8 with large files
#
# IO#sendfile currently (June 2010) beats 1.9 IO.copy_stream with
# non-Linux support and large files on 32-bit.  We still fall back to
# IO.copy_stream (if available) if we're dealing with DevFdResponse
# objects, though.
#
# Linux-only splice(2) support via the "io_splice" gem will eventually
# be added for streaming sockets/pipes, too.
#
# * write_body_file - regular files (sendfile or pread+write)
# * write_body_stream - socket/pipes (read+write, splice later)
# * write_body_each - generic fallback
#
# callgraph is as follows:
#
#         write_body
#         `- write_body_each
#         `- write_body_path
#            `- write_body_file
#            `- write_body_stream
#
module Rainbows::Response::Body # :nodoc:
  ALIASES = {}

  FD_MAP = Rainbows::FD_MAP

  class F < File; end

  def close_if_private(io)
    io.close if F === io
  end

  def io_for_fd(fd)
    FD_MAP.delete(fd) || F.for_fd(fd)
  end

  # to_io is not part of the Rack spec, but make an exception here
  # since we can conserve path lookups and file descriptors.
  # \Rainbows! will never get here without checking for the existence
  # of body.to_path first.
  def body_to_io(body)
    if body.respond_to?(:to_io)
      body.to_io
    else
      # try to take advantage of Rainbows::DevFdResponse, calling File.open
      # is a last resort
      path = body.to_path
      path =~ %r{\A/dev/fd/(\d+)\z} ? io_for_fd($1.to_i) : F.open(path)
    end
  end

  if IO.method_defined?(:sendfile_nonblock)
    def write_body_file_sendfile(sock, body, range)
      io = body_to_io(body)
      range ? sock.sendfile(io, range[0], range[1]) : sock.sendfile(io, 0)
      ensure
        close_if_private(io)
    end
    ALIASES[:write_body_file] = :write_body_file_sendfile
  end

  if IO.respond_to?(:copy_stream)
    unless method_defined?(:write_body_file_sendfile)
      # try to use sendfile() via IO.copy_stream, otherwise pread()+write()
      def write_body_file_copy_stream(sock, body, range)
        range ? IO.copy_stream(body, sock, range[1], range[0]) :
                IO.copy_stream(body, sock, nil, 0)
      end
      ALIASES[:write_body_file] = :write_body_file_copy_stream
    end

    # only used when body is a pipe or socket that can't handle
    # pread() semantics
    def write_body_stream(sock, body)
      IO.copy_stream(body, sock)
    end
  else
    # fall back to body#each, which is a Rack standard
    ALIASES[:write_body_stream] = :write_body_each
  end

  if ALIASES[:write_body_file]
    # middlewares/apps may return with a body that responds to +to_path+
    def write_body_path(sock, body, range)
      File.file?(body.to_path) ? write_body_file(sock, body, range) :
                                 write_body_stream(sock, body)
      ensure
        body.respond_to?(:close) and body.close
    end
  end

  if method_defined?(:write_body_path)
    def write_body(client, body, range)
      body.respond_to?(:to_path) ?
        write_body_path(client, body, range) :
        write_body_each(client, body)
    end
  else
    ALIASES[:write_body] = :write_body_each
  end

  # generic body writer, used for most dynamically generated responses
  def write_body_each(socket, body, range = nil)
    body.each { |chunk| socket.write(chunk) }
    ensure
      body.respond_to?(:close) and body.close
  end

  def self.included(klass)
    ALIASES.each do |new_method, orig_method|
      klass.__send__(:alias_method, new_method, orig_method)
    end
  end
end
