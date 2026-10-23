# frozen_string_literal: true

module CtxCli
  # 普通参数分组只登记语法；不加载配置、不执行操作、不拥有领域校验。
  module Options
    def self.initialization(parser, values)
      parser.on("--init", "Create missing configuration and environment templates, then exit; preserve existing files") { values[:init] = true }
      parser.on("--interactive", "Prompt to create missing configuration; requires an interactive terminal") { values[:interactive] = true }
      parser.on("--non-interactive", "Disable prompts; specify --init to create files") { values[:interactive] = false }
    end

    def self.output(parser, values, quiet: :quiet)
      parser.on("--json", "Write JSON to stdout; defaults to a readable summary") { values[:json] = true }
      parser.on("--quiet", "--no-progress", "Disable progress on stderr; can be combined with --json") { values[quiet] = true }
      parser.on("--verbose", "Show per-device results and safe command events") { values[:verbose] = true }
    end

    def self.information(parser, values)
      parser.on("-h", "--help", "Show option help") { values[:help] = true }
      parser.on("--help-all", "Show all options, paths and environment conventions") { values[:help_all] = true }
      parser.on("--examples", "Show common command examples without executing tasks") { values[:examples] = true }
    end

    # 值转换留在宿主边界，允许不同入口沿用原有存储格式。
    def self.configuration(parser, parallel_help: "Device concurrency", &store)
      parser.on("--config FILE", "Overlay explicit YAML after automatically discovered configuration") { |value| store.call(:config, value) }
      parser.on("--env-file FILE", "Load explicit environment files last; process environment takes precedence") { |value| store.call(:env_file, value) }
      parser.on("-p", "--parallel N", Integer, parallel_help) { |value| store.call(:parallel, value) }
      parser.on("--directory DIR", "Directory for per-device reports") { |value| store.call(:directory, value) }
    end

    def self.list(value)
      values = value.split(",", -1).map(&:strip)
      raise ArgumentError, "Lists must not contain empty entries" if values.any?(&:empty?)
      values
    end
  end
end
