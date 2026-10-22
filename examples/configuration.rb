# frozen_string_literal: true

require "ctx_cli"
require "tmpdir"

# 自定义宿主命名空间；示例只操作临时目录，不读取真实用户配置。
Dir.mktmpdir do |root|
  path = File.join(root, "audit.yml")
  publisher = CtxCli::Initialization.new
  abort "Initialization failed" unless publisher.create(path: path, contents: "directory: reports\nparallel: 2\n") == :created
  files = CtxCli::Configuration.new(name: "audit", env: {}, directories: [ root ], path_fields: [ "directory" ]).load
  effective = CtxCli::Configuration.merge({ "parallel" => 1 }, files.data, { "parallel" => 4 })
  abort "Unexpected precedence" unless effective == { "directory" => File.join(root, "reports"), "parallel" => 4 }
  abort "Existing configuration overwritten" unless publisher.create(path: path, contents: "invalid") == :exists
end
puts "Configuration discovery and private initialization verified"
