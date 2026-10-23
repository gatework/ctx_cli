# frozen_string_literal: true

require "optparse"
require_relative "configuration"

module CtxCli
  # 每次解析新建值与解析器；领域参数通过普通 OptionParser 块扩展。
  class Command
    attr_reader :values, :parser

    def initialize(banner:, defaults: {}, out: $stdout, &configure)
      @banner, @defaults, @out, @configure = banner, Configuration.copy(defaults), out, configure
    end

    def parse(argv)
      @values = Configuration.copy(@defaults)
      @parser = OptionParser.new
      @parser.banner = @banner
      @configure&.call(@parser, @values)
      rest = @parser.parse(argv.dup)
      raise ArgumentError, "Positional arguments are not accepted" unless rest.empty?
      @values
    end

    # 信息分支只写指定输出流，调用方在此后才读取输入或配置。
    def informational?(examples: nil, details: nil)
      if values[:help] || values[:help_all]
        @out.puts parser
        @out.puts details if values[:help_all] && details
      elsif values[:examples] && examples
        @out.puts examples
      else
        return false
      end
      true
    end

    def inspect = "#<#{self.class.name}>"
    alias_method :to_s, :inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
