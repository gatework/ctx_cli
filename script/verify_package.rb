# frozen_string_literal: true

require "rubygems/package"
require "tmpdir"
require "rbconfig"
require "fileutils"
require "bundler"

artifact = File.expand_path(ARGV.fetch(0))
package = Gem::Package.new(artifact)
package.verify
spec = package.spec
abort "Unexpected package" unless spec.name == "ctx_cli"
abort "Unexpected package contents" if spec.files.any? { |path| path.start_with?("spec/", "test/", "storage/", "tmp/") || path.end_with?(".log", ".gem") }

# 只使用运行时依赖闭包的缓存，最小消费者不能借用开发 Gemfile。
dependencies, pending = {}, spec.runtime_dependencies.dup
until pending.empty?
  dependency = pending.shift
  next if dependencies.key?(dependency.name)
  selected = Gem::Specification.find_all_by_name(dependency.name, dependency.requirement).max_by(&:version)
  abort "Missing local dependency: #{dependency.name}" unless selected
  dependencies[selected.name] = selected
  pending.concat(selected.runtime_dependencies)
end
dependencies["bundler"] = Gem.loaded_specs.fetch("bundler")

Dir.mktmpdir("ctx-cli-install-") do |root|
  home = File.join(root, "gems")
  env = ENV.to_h.keys.grep(/\A(?:BUNDLE_|BUNDLER_|RUBY)/).to_h { |key| [ key, nil ] }
  env.merge!("GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_IGNORE_CONFIG" => "true")
  dependencies.each_value do |dependency|
    if File.file?(dependency.cache_file)
      FileUtils.cp(dependency.cache_file, root)
    elsif !dependency.default_gem?
      abort "Missing dependency cache: #{dependency.full_name}"
    end
  end
  ruby = RbConfig.ruby
  system(env, ruby, "-S", "gem", "install", artifact, "--local", "--no-document", chdir: root, exception: true)
  bundler = dependencies.fetch("bundler")
  if File.file?(bundler.cache_file)
    system(env, ruby, "-S", "gem", "install", File.join(root, File.basename(bundler.cache_file)), "--local", "--no-document", chdir: root, exception: true)
  end
  check = <<~RUBY
    require "ctx_cli"
    abort "Unexpected host dependency" if defined?(Rails) || defined?(CtxRunner) || defined?(CtxParser) || defined?(Net::Connector)
    loaded = Gem.loaded_specs.fetch("ctx_cli")
    abort "Loaded checkout instead of package" unless File.realpath(loaded.full_gem_path).start_with?(File.realpath(ENV.fetch("GEM_HOME")) + "/")
    abort "Version mismatch" unless loaded.version.to_s == #{spec.version.to_s.inspect}
    Dir[File.join(loaded.full_gem_path, "examples/**/*.rb")].sort.each { |path| load path }
  RUBY
  File.write(File.join(root, "smoke.rb"), check)
  system(env, ruby, "smoke.rb", chdir: root, exception: true)
  File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\ngem \"ctx_cli\", \"= #{spec.version}\"\n")
  system(env, ruby, "-S", "bundle", "_#{bundler.version}_", "lock", "--local", chdir: root, exception: true)
  system(env, ruby, "-S", "bundle", "_#{bundler.version}_", "exec", ruby, "smoke.rb", chdir: root, exception: true)
end
