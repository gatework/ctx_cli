# frozen_string_literal: true

require "json"

module CtxCli
  # 结果显式导出；诊断不展开异常正文，输出失败不能伪装结果成功。
  class Output
    def initialize(out: $stdout, error: $stderr)
      @out, @error = out, error
    end

    def text(value) = @out.puts(value)
    def json(value, pretty: true) = @out.puts(pretty ? JSON.pretty_generate(value) : JSON.generate(value))

    # 最后的错误流失败不能覆盖原本的失败或取消状态。
    def diagnostic(message, exception: nil)
      @error.puts(exception ? "#{message}（#{exception.class.name}）" : message)
    rescue StandardError
      nil
    end
  end
end
