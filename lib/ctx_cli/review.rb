# frozen_string_literal: true

require "json"
require_relative "input"
require_relative "output"

module CtxCli
  # 离线入口先读取并预检全部来源，再允许领域适配器创建报告。
  class Review
    MAX_FILES = 10_000
    MAX_TOTAL_BYTES = 64 * 1024 * 1024

    def initialize(command:, directory:, adapter:, out: $stdout, error: $stderr,
                   max_files: MAX_FILES, max_bytes: Input::MAX_BYTES, max_total_bytes: MAX_TOTAL_BYTES)
      unless [ max_files, max_bytes, max_total_bytes ].all? { |limit| limit.is_a?(Integer) && limit.positive? }
        raise ArgumentError, "review budgets must be positive integers"
      end
      @max_files, @max_bytes, @max_total_bytes = max_files, max_bytes, max_total_bytes
      @command, @directory, @adapter = command, directory, adapter
      @output = Output.new(out: out, error: error)
    end

    def run(argv)
      options = @command.parse(argv)
      return 0 if @command.informational?
      raise ArgumentError, "A batch directory is required" unless options[:batch]
      batch = File.expand_path(options[:batch])
      paths = source_paths(File.join(batch, @directory))
      raise ArgumentError, "No device reports found" if paths.empty?
      remaining = @max_total_bytes
      sources = paths.map do |path|
        raise ArgumentError, "review byte budget exceeded" unless remaining.positive?
        body = Input.read(path: path, max_bytes: [ @max_bytes, remaining ].min)
        remaining -= body.bytesize
        [ path, body, JSON.parse(body) ]
      end
      context = @adapter.prepare(sources, options)
      @output.text(@adapter.publish(sources, options, batch: batch, context: context))
      0
    rescue Interrupt
      @output.diagnostic("Review cancelled; existing reports retained; no device changes executed.")
      130
    rescue StandardError => error
      @output.diagnostic("Review failed (#{error.class.name}); check the input structure, directory permissions and --help; no device changes executed.")
      2
    end

    def inspect = "#<#{self.class.name}>"
    alias_method :to_s, :inspect
    def pretty_print(printer) = printer.text(inspect)

    private

    # 目录名按字面处理；边枚举边限制数量，避免先创建无限制的路径数组。
    def source_paths(directory)
      paths = []
      Dir.each_child(directory) do |name|
        next if name.start_with?(".") || !name.end_with?(".json")
        raise ArgumentError, "review file budget exceeded" if paths.size >= @max_files
        paths << File.join(directory, name)
      end
      paths.sort
    end
  end
end
