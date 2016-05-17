# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Response
  include Unicorn::HttpResponse
  Close = "close"
  KeepAlive = "keep-alive"
  Content_Length = "Content-Length".freeze
  Transfer_Encoding = "Transfer-Encoding".freeze
  Rainbows.config!(self, :copy_stream)

  # private file class for IO objects opened by Rainbows! itself (and not
  # the app or middleware)
  class F < File; end

  # called after forking
  def self.setup
    Kgio.accept_class = Rainbows::Client
    0 == Rainbows.server.keepalive_timeout and
      Rainbows::HttpParser.keepalive_requests = 0
  end

  # Rack 1.5.0 (protocol version 1.2) adds response hijacking support
  if ((Rack::VERSION[0] << 8) | Rack::VERSION[1]) >= 0x0102
    RACK_HIJACK = "rack.hijack"

    def hijack_prepare(value)
      value
    end

    def hijack_socket
      @hp.env[RACK_HIJACK].call
    end
  else
    def hijack_prepare(_)
    end
  end

  # returns the original body on success
  # returns nil if the headers hijacked the response body
  def write_headers(status, headers, alive, body)
    @hp.headers? or return body
    hijack = nil
    status = CODES[status.to_i] || status
    buf = "HTTP/1.1 #{status}\r\n" \
          "Date: #{httpdate}\r\n" \
          "Status: #{status}\r\n"
    logger.info "====== #{headers.inspect} ======"
    headers.each do |key, value|
      logger.info "====== key: #{key.inspect} value: #{value.inspect} ======"
      case key
      when %r{\A(?:Date\z|Connection\z)}i
        next
      when "rack.hijack"
        # this was an illegal key in Rack < 1.5, so it should be
        # OK to silently discard it for those older versions
        hijack = hijack_prepare(value)
        alive = false # No persistent connections for hijacking
      else
        logger.info "====== HERE!!! ======"
        if /\n/ =~ value
          # avoiding blank, key-only cookies with /\n+/
          buf << value.split(/\n+/).map! { |v| "#{key}: #{v}\r\n" }.join
        else
          buf << "#{key}: #{value}\r\n"
        end
      end
    end
    write(buf << "Connection: #{alive ? KeepAlive : Close}\r\n\r\n")

    if hijack
      body = nil # ensure caller does not close body
      hijack.call(hijack_socket)
    end
    body
  end

  def close_if_private(io)
    io.close if F === io
  end

  def io_for_fd(fd)
    Rainbows::FD_MAP.delete(fd) || F.for_fd(fd)
  end

  # to_io is not part of the Rack spec, but make an exception here
  # since we can conserve path lookups and file descriptors.
  # \Rainbows! will never get here without checking for the existence
  # of body.to_path first.
  def body_to_io(body)
    if body.respond_to?(:to_io)
      body.to_io
    else
      # try to take advantage of Rainbows::DevFdResponse, calling F.open
      # is a last resort
      path = body.to_path
      %r{\A/dev/fd/(\d+)\z} =~ path ? io_for_fd($1.to_i) : F.open(path)
    end
  end

  module Each
    # generic body writer, used for most dynamically-generated responses
    def write_body_each(body)
      body.each { |chunk| write(chunk) }
    end

    # generic response writer, used for most dynamically-generated responses
    # and also when copy_stream and/or IO#trysendfile is unavailable
    def write_response(status, headers, body, alive)
      body = write_headers(status, headers, alive, body)
      write_body_each(body) if body
      body
      ensure
        body.close if body.respond_to?(:close)
    end
  end
  include Each

  if IO.method_defined?(:trysendfile)
    module Sendfile
      def write_body_file(body, range)
        io = body_to_io(body)
        range ? sendfile(io, range[0], range[1]) : sendfile(io, 0)
        ensure
          close_if_private(io)
      end
    end
    include Sendfile
  end

  if COPY_STREAM
    unless IO.method_defined?(:trysendfile)
      module CopyStream
        def write_body_file(body, range)
          range ? COPY_STREAM.copy_stream(body, self, range[1], range[0]) :
                  COPY_STREAM.copy_stream(body, self, nil, 0)
        end
      end
      include CopyStream
    end

    # write_body_stream is an alias for write_body_each if copy_stream
    # isn't used or available.
    def write_body_stream(body)
      COPY_STREAM.copy_stream(io = body_to_io(body), self)
      ensure
        close_if_private(io)
    end
  else # ! COPY_STREAM
    alias write_body_stream write_body_each
  end  # ! COPY_STREAM

  if IO.method_defined?(:trysendfile) || COPY_STREAM
    HTTP_RANGE = 'HTTP_RANGE'
    Content_Range = 'Content-Range'.freeze

    # This does not support multipart responses (does anybody actually
    # use those?)
    def sendfile_range(status, headers)
      status = status.to_i
      if 206 == status
        if %r{\Abytes (\d+)-(\d+)/\d+\z} =~ headers[Content_Range]
          a, b = $1.to_i, $2.to_i
          return 206, headers, [ a,  b - a + 1 ]
        end
        return # wtf...
      end
      200 == status &&
      /\Abytes=(\d+-\d*|\d*-\d+)\z/ =~ @hp.env[HTTP_RANGE] or
        return
      a, b = $1.split(/-/)

      # HeaderHash is quite expensive, and Rack::File currently
      # uses a regular Ruby Hash with properly-cased headers the
      # same way they're presented in rfc2616.
      headers = Rack::Utils::HeaderHash.new(headers) unless Hash === headers
      clen = headers[Content_Length] or return
      size = clen.to_i

      if b.nil? # bytes=M-
        offset = a.to_i
        count = size - offset
      elsif a.empty? # bytes=-N
        offset = size - b.to_i
        count = size - offset
      else  # bytes=M-N
        offset = a.to_i
        count = b.to_i + 1 - offset
      end

      if 0 > count || offset >= size
        headers[Content_Length] = "0"
        headers[Content_Range] = "bytes */#{clen}"
        return 416, headers, nil
      else
        count = size if count > size
        headers[Content_Length] = count.to_s
        headers[Content_Range] = "bytes #{offset}-#{offset+count-1}/#{clen}"
        return 206, headers, [ offset, count ]
      end
    end

    def write_response_path(status, headers, body, alive)
      if File.file?(body.to_path)
        if r = sendfile_range(status, headers)
          status, headers, range = r
          body = write_headers(status, headers, alive, body)
          write_body_file(body, range) if body && range
        else
          body = write_headers(status, headers, alive, body)
          write_body_file(body, nil) if body
        end
      else
        body = write_headers(status, headers, alive, body)
        write_body_stream(body) if body
      end
      body
      ensure
        body.close if body.respond_to?(:close)
    end

    module ToPath
      # returns nil if hijacked
      def write_response(status, headers, body, alive)
        if body.respond_to?(:to_path)
          write_response_path(status, headers, body, alive)
        else
          super
        end
      end
    end
    include ToPath
  end # COPY_STREAM || IO.method_defined?(:trysendfile)
end
