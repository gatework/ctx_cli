# frozen_string_literal: true

module CtxCli
  # 只关闭自行打开的文件，stdin 的读取和关闭权仍由宿主控制。
  module Input
    def self.read(path: nil, input: $stdin)
      path ? File.read(path) : input.read
    end
  end
end
