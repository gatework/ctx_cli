# frozen_string_literal: true

module CtxCli
  # 终端只借用标准流；确认、问答和密码读取都由调用方显式发起。
  class Terminal
    def initialize(input: $stdin, out: $stderr)
      @input, @out = input, out
    end

    def self.tty?(*streams) = streams.all? { |stream| stream.respond_to?(:tty?) && stream.tty? }
    def tty?(*others) = self.class.tty?(@input, @out, *others)

    def require_tty!(*others, message: "必须使用真实交互终端")
      raise ArgumentError, message unless tty?(*others)
    end

    def question(prompt)
      require_tty!
      @out.print prompt
      @out.flush
      @input.gets("\n")&.strip
    end

    def confirm(token:, prompt:)
      question(prompt) == token
    end

    def password(label:)
      raise ArgumentError, "密码提示需要交互终端；自动化任务可使用环境变量或 --stdin-credentials" unless self.class.tty?(@input)
      require "io/console"
      @out.print "#{label}："
      @out.flush
      value = @input.noecho { |terminal| terminal.gets("\n") }&.chomp("\n")
      @out.puts
      raise ArgumentError, "密码不能为空" if value.nil? || value.empty?
      value
    end
  end
end
