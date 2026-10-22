# frozen_string_literal: true

require "ctx_cli"
require "stringio"

# 领域只声明自己的参数和动作；标准流始终由宿主拥有。
out = StringIO.new
command = CtxCli::Command.new(banner: "sample [--complete]", defaults: { complete: false }, out: out) do |parser, values|
  parser.on("--complete", "声明输入采集完整") { values[:complete] = true }
  CtxCli::Options.information(parser, values)
end
values = command.parse([ "--complete" ])
body = CtxCli::Input.read(input: StringIO.new("synthetic evidence"))
CtxCli::Output.new(out: out).json({ complete: values[:complete], bytes: body.bytesize })
abort "Unexpected offline output" unless JSON.parse(out.string) == { "complete" => true, "bytes" => 18 }
puts "Offline command boundary verified"
