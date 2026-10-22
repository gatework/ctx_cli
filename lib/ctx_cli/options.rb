# frozen_string_literal: true

module CtxCli
  # 普通参数分组只登记语法；不加载配置、不执行操作、不拥有领域校验。
  module Options
    def self.initialization(parser, values)
      parser.on("--init", "创建缺失配置和环境模板后退出；已有文件不覆盖") { values[:init] = true }
      parser.on("--interactive", "缺少配置时询问是否创建；要求真实终端") { values[:interactive] = true }
      parser.on("--non-interactive", "禁用问答；创建文件须同时指定 --init") { values[:interactive] = false }
    end

    def self.output(parser, values, quiet: :quiet)
      parser.on("--json", "stdout 输出 JSON；默认显示可读摘要") { values[:json] = true }
      parser.on("--quiet", "--no-progress", "关闭 stderr 进度，可配合 --json") { values[quiet] = true }
      parser.on("--verbose", "显示逐台结果及安全命令事件") { values[:verbose] = true }
    end

    def self.information(parser, values)
      parser.on("-h", "--help", "查看选项帮助") { values[:help] = true }
      parser.on("--help-all", "查看全部选项、路径与环境约定") { values[:help_all] = true }
      parser.on("--examples", "查看常用命令范例，不执行任务") { values[:examples] = true }
    end

    # 值转换留在宿主边界，允许不同入口沿用原有存储格式。
    def self.configuration(parser, parallel_help: "设备并发数", &store)
      parser.on("--config FILE", "显式 YAML 最后叠加于自动发现的配置") { |value| store.call(:config, value) }
      parser.on("--env-file FILE", "显式环境文件最后叠加；进程环境优先") { |value| store.call(:env_file, value) }
      parser.on("-p", "--parallel N", Integer, parallel_help) { |value| store.call(:parallel, value) }
      parser.on("--directory DIR", "按设备保存报告的目录") { |value| store.call(:directory, value) }
    end

    def self.list(value)
      values = value.split(",", -1).map(&:strip)
      raise ArgumentError, "列表不能有空项" if values.any?(&:empty?)
      values
    end
  end
end
