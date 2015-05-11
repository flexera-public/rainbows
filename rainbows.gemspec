# -*- encoding: binary -*-
ENV["VERSION"] ||= File.read(File.expand_path('../lib/rainbows/version.rb', __FILE__)).match(/.*'([^']*)'.*/).captures.first

Gem::Specification.new do |s|
  s.name = %q{rainbows}
  s.version = ENV["VERSION"].dup

  s.authors = "Rainbows! hackers"
  s.date = Time.now.utc.strftime('%Y-%m-%d')
  s.description = "\Rainbows! is an HTTP server for sleepy Rack applications.  It is based on " +
    "Unicorn, but designed to handle applications that expect long " +
    "request/response times and/or slow clients."
  s.email = %q{rainbows-public@bogomips.org}
  s.executables = %w(rainbows)
  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(archive|examples|t|Documentation)/}) }
  s.summary = "Unicorn for sleepy apps and slow clients"
  s.rubyforge_project = %q{rainbows}

  # we want a newer Rack for a valid HeaderHash#each
  s.add_dependency(%q<rack>, ['~> 1.1'])

  # kgio 2.5 has kgio_wait_* methods that take optional timeout args
  s.add_dependency(%q<kgio>, ['~> 2.5'])

  # we need Unicorn for the HTTP parser and process management
  # we need unicorn 4.8.0+ since we depend on undocumented/unsupported
  # unicorn internals.
  s.add_dependency(%q<unicorn>, ["~> 4.8"])

  s.add_development_dependency(%q<isolate>, "~> 3.1")
  s.add_development_dependency(%q<wrongdoc>, "~> 1.8")

  # optional runtime dependencies depending on configuration
  # see t/test_isolate.rb for the exact versions we've tested with
  #
  # Revactor >= 0.1.5 includes UNIX domain socket support
  # s.add_dependency(%q<revactor>, [">= 0.1.5"])
  #
  # Revactor depends on Rev, too, 0.3.0 got the ability to attach IOs
  # s.add_dependency(%q<rev>, [">= 0.3.2"])
  #
  # Cool.io is the new Rev, but it doesn't work with Revactor
  # s.add_dependency(%q<cool.io>, [">= 1.0"])
  #
  # Rev depends on IOBuffer, which got faster in 0.1.3
  # s.add_dependency(%q<iobuffer>, [">= 0.1.3"])
  #
  # We use the new EM::attach/watch API in 0.12.10
  # s.add_dependency(%q<eventmachine>, ["~> 0.12.10"])
  #
  # NeverBlock, currently only available on http://gems.github.com/
  # s.add_dependency(%q<espace-neverblock>, ["~> 0.1.6.1"])

  # We inherited the Ruby 1.8 license from Mongrel, so we're stuck with it.
  # GPLv3 is preferred.
  s.licenses = ["GPLv2+", "Ruby 1.8"]
end
