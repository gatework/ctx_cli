# frozen_string_literal: true

require_relative "lib/ctx_cli/version"

Gem::Specification.new do |spec|
  spec.name = "ctx_cli"
  spec.version = CtxCli::VERSION
  spec.authors = [ "Gatework contributors" ]
  spec.summary = "Composable command-line boundaries for network automation."
  spec.description = "Shared configuration discovery, private initialization, terminal interaction and CLI orchestration without device or application dependencies."
  spec.homepage = "https://github.com/gatework/ctx_cli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}#readme",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }
  # 显式限定打包内容，设备数据、凭据和验证产物不进入 gem。
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "examples/**/*.rb", "docs/**/*.md", "README*.md", "CHANGELOG.md", "LICENSE"].sort }
  spec.require_paths = [ "lib" ]
  spec.add_dependency "dotenv"
  %w[fileutils io-console json optparse tempfile yaml].each { |name| spec.add_dependency name }
end
