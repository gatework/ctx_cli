# frozen_string_literal: true

require "digest"
require "json"
require_relative "command"
require_relative "configuration"
require_relative "terminal"
require_relative "input"
require_relative "output"

module CtxCli
  # 单项交互变更的终端入口；领域校验与会话、执行账本均通过显式协作者提供。
  class Apply
    def initialize(adapter:, execution:, name:, out: $stdout, error: $stderr, input: $stdin)
      @adapter, @execution_class, @name = adapter, execution, name
      @out, @error, @input = out, error, input
      @output = Output.new(out: out, error: error)
    end

    def run(argv)
      @execution = nil
      command = options
      values = command.parse(argv)
      return 0 if command.informational?
      terminal = Terminal.new(input: @input, out: @out)
      terminal.require_tty!(@error)
      unless values[:plan] && values[:item] && values[:port].between?(1, 65_535)
        raise ArgumentError, "A plan and explicit --item are required"
      end
      body = Input.read(path: values[:plan])
      sha256 = Digest::SHA256.hexdigest(body)
      unless Input.read(path: "#{values[:plan]}.sha256", max_bytes: 128).strip == sha256
        raise ArgumentError, "Plan checksum verification failed"
      end
      # 外部领域回调不能改变刚验证的计划、选择或连接参数。
      values = Configuration.freeze_tree(Configuration.copy(values))
      document = Configuration.freeze_tree(Configuration.copy(JSON.parse(body, max_nesting: 128)))
      plan = Configuration.freeze_tree(Configuration.copy(@adapter.select_plan(document, item: values[:item])))
      change = @adapter.validate_plan(plan)
      host = plan.fetch("target").fetch("host")
      @out.puts "Target: #{plan['target']['name']}(#{host}); #{plan['scope']}; #{plan['title']}"
      @out.puts "Impact: #{plan['impact']}"
      @out.puts Array(plan["prerequisites"]).map { |value| "Prerequisite: #{value}" }
      @out.puts "Plan SHA256: #{sha256}\nProposed commands:\n#{change.commands.join("\n")}\nConditional rollback (not executed automatically):\n#{change.rollback.join("\n")}"
      token = "APPLY #{host} #{sha256[0, 12]} #{values[:item]}"
      unless terminal.confirm(token: token, prompt: "After reviewing the service policy and maintenance window, enter #{token}; any other input cancels: ")
        @out.puts "Cancelled; no device connection opened."
        return 1
      end
      settings = @adapter.credentials(values)
      journal = @adapter.report(values)
      @execution = @execution_class.new(plan: plan, change: change, journal: journal, plan_sha256: sha256, item: values[:item])
      @execution.run { |operation| @adapter.with_session(plan.fetch("target"), settings, &operation) }
      @out.puts "Configuration readback confirmed; service acceptance is still required. Configuration was not saved to startup configuration. Log: #{journal.directory}/execution.json"
      0
    rescue Interrupt
      failure("Operation interrupted")
      130
    rescue StandardError, LoadError => error
      failure("Apply stopped (#{error.class.name})")
      2
    end

    def inspect = "#<#{self.class.name}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)

    private

    def options
      Command.new(banner: "Usage: #{@name} apply --plan FILE --item ID [--env-file FILE] (interactive confirmation required)",
        defaults: { directory: File.join(Dir.pwd, "#{@name}-executions"), port: 22 }, out: @out) do |parser, values|
        parser.on("--plan FILE", "Versioned plan with an adjacent .sha256 checksum") { |value| values[:plan] = value }
        parser.on("--item ID", "Explicitly select one change") { |value| values[:item] = value }
        parser.on("--env-file FILE", "Credentials file; process environment takes precedence") { |value| values[:env_file] = value }
        parser.on("--directory DIR", "Private execution journal directory") { |value| values[:directory] = value }
        parser.on("--port N", Integer, "SSH port, default 22") { |value| values[:port] = value }
        parser.on("-h", "--help", "Show help") { values[:help] = true }
      end
    end

    def failure(message)
      if @execution&.journal_failed?
        @output.diagnostic "Execution log finalization is unconfirmed; existing checkpoints retained."
      end
      detail = @execution&.started? ? "Effects are uncertain; read back before proceeding. Do not replay commands." : "No service configuration was sent."
      @output.diagnostic "#{message}; #{detail}"
    rescue Interrupt
      nil
    end
  end
end
