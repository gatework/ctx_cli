# frozen_string_literal: true

module CtxCli
  # 只关闭自行打开的文件，stdin 的读取和关闭权仍由宿主控制。
  module Input
    MAX_BYTES = 16 * 1024 * 1024

    def self.read(path: nil, input: $stdin, max_bytes: MAX_BYTES)
      raise ArgumentError, "input byte budget must be positive" unless max_bytes.is_a?(Integer) && max_bytes.positive?
      return File.open(path, "r") { |file| read(input: file, max_bytes: max_bytes) } if path
      contents = input.read(max_bytes + 1) || +""
      raise ArgumentError, "input exceeds byte budget" if contents.bytesize > max_bytes
      contents.force_encoding(input.external_encoding || Encoding.default_external)
    end
  end
end
