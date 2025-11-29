# frozen_string_literal: true

# Patch rspec-parameterized-core to use prism parser for Ruby < 3.4
# This fixes ProcToAst::MultiMatchError issues caused by parser gem version mismatch
# (parser 3.3.10 expects Ruby 3.3.10 syntax but we're running Ruby 3.3.x)
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4.0')
  require 'prism'

  module RSpec::Parameterized::Core::CompositeParser
    def self.use_prism?
      true
    end
  end
end
