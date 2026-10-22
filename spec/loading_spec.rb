# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "Independent entrypoint loading" do
  it "loads every capability in a fresh process without host libraries or user configuration" do
    paths = Dir[File.expand_path("../lib/ctx_cli/*.rb", __dir__)].map { |path| "ctx_cli/#{File.basename(path, '.rb')}" }
    [ "ctx_cli", *paths ].each do |path|
      script = <<~RUBY
        require #{path.inspect}
        abort "Unexpected host dependency" if defined?(Rails) || defined?(CtxRunner) || defined?(CtxParser) || defined?(Net::Connector)
        abort "Modified environment" unless ENV["AUDIT_CONFIG"] == "/missing/never-read.yml"
      RUBY
      output, error, status = Open3.capture3({ "AUDIT_CONFIG" => "/missing/never-read.yml" }, RbConfig.ruby, "-Ilib", "-e", script)
      expect(status).to be_success, "#{path}: #{error}"
      expect(output).to eq("")
    end
  end
end
