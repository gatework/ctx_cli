# frozen_string_literal: true

require "bundler/setup"
require "rspec/core"
require "ctx_cli"
require "tmpdir"
require "stringio"

RSpec.configure do |config|
  config.order = :random
  config.disable_monkey_patching!
end
