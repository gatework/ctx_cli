# frozen_string_literal: true

module CtxCli
  # 命令工厂按需执行；帮助和版本不加载领域实现或配置。
  class Router
    def initialize(name:, version:, usage:, commands:, out: $stdout, error: $stderr)
      @name, @version, @usage, @commands = name, version, usage, commands.dup.freeze
      @out, @error = out, error
    end

    # 退出行为归调用方；保留 argv 并只返回命令退出码。
    def run(argv)
      arguments = argv.map { |argument| String.new(argument) }
      command = arguments.shift
      if [ nil, "--help", "--help-all", "-h" ].include?(command) && arguments.empty?
        @out.puts @usage
        return 0
      end
      if %w[--version -v].include?(command) && arguments.empty?
        @out.puts @version
        return 0
      end
      return @commands.fetch(command).call(arguments) if @commands.key?(command)
      @error.puts "未知命令或多余参数；使用 #{@name} --help 查看用法"
      2
    end
  end
end
