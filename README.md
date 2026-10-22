# ctx_cli

可组合的 Ruby 命令行基础库，用于减少网络自动化模块的入口样板代码。它处理配置、终端和入口流程，领域模块继续拥有厂商语法、业务校验、清单选择及设备能力。

## 公共能力

| 对象 | 职责 |
| --- | --- |
| `Application` | 惰性子命令分发、全局帮助/版本、返回退出码 |
| `Command` / `Options` | 每次独立的参数快照、信息分支、公共 OptionParser 分组 |
| `Configuration` | 多层文件发现、隔离环境、来源路径、纯数据快照 |
| `Initialization` | 私有文件排他创建、同步、保留已有配置 |
| `Terminal` | 真实终端检查、问答、隐藏密码、完整 token 确认 |
| `Input` / `Output` | 文件/stdin、显式 JSON、仅含错误类型的诊断 |
| `Collection` | 配置、预览、全批预检、调度交付及退出码映射 |

Ruby >= 3.4。`require "ctx_cli"` 或按能力加载 `ctx_cli/configuration` 等路径；加载不读取用户文件、不修改 ENV、不建立网络连接。核心不依赖 ctx_parser、ctx_runner 或 net-connector。代码和工程规范参照 ctx_parser，保留 Ruby 3.4 是为了兼容现有 backup 宿主。

## 少写入口代码

```ruby
require "ctx_cli"

command = CtxCli::Command.new(banner: "audit [选项]", defaults: { complete: false }) do |parser, values|
  parser.on("--file FILE") { |path| values[:file] = path }
  parser.on("--complete") { values[:complete] = true }
  CtxCli::Options.information(parser, values)
end
values = command.parse(ARGV)
unless command.informational?(examples: "audit --file running.cfg --complete")
  body = CtxCli::Input.read(path: values[:file])
  # 调用自己的领域 API；完整采集与业务健康由领域分别判断。
  CtxCli::Output.new.json({ bytes: body.bytesize, complete: values[:complete] })
end
```

库方法不调用 exit。宿主自己决定参数错误、部分结果、取消对应的退出码。`Command#parse` 不接受位置参数，每次重建默认值和 OptionParser；配置块必须将本次值写入块参数，不缓存上次的值容器。特殊参数直接用 OptionParser，不要求继承或注册 DSL。

`Options.configuration(parser) { |key, value| ... }` 登记 config/env_file/parallel/directory；`parallel_help:` 可说明宿主自己的并发范围、默认值与环境变量。`Options.initialization`、`output`、`information` 接收当前标记 Hash。值转换、公开字段允许列表、层级优先级和领域校验属于宿主。

## 配置与初始化

```ruby
files = CtxCli::Configuration.new(
  name: "audit", namespace: "network-tools", names: %w[audit backup],
  common_keys: %w[ssh inventory], config_env: "AUDIT_CONFIG",
  path_fields: %w[directory ssh.known_hosts], env_path_keys: %w[AUDIT_DIRECTORY]
).load

files.data        # 深冻结的 YAML 合并结果
files.environment # .env 加原进程环境；不修改 ENV
files.sources     # 路径与字段来源，不包含环境值
```

默认依次搜索 `/etc/<namespace>`、`/usr/local/etc/<namespace>`、`$XDG_CONFIG_HOME/<namespace>`（否则 `~/.config/<namespace>`）、入口目录和启动目录。每层读取 `<namespace>.yml` 与 `<name>.yml`，显式文件最后。共享文件按 `common` 和工具名称分区；name 与 namespace 相同时使用普通独立文件。`directories:` 可以完整替换搜索范围。

宿主把各层公共环境值转换成领域字段后，通过 `Configuration.merge(defaults, dotenv_values, yaml, process_values, cli)` 实现 CLI > 进程环境 > YAML > .env > 默认值。数组整层替换，false/nil 保留。相对路径按来源目录解释；支持 `path_literals:`（如 `system`）和 URI。`load` 重复调用不重新读文件。

`Initialization#create(path:, contents:)` 返回 `:created` 或 `:exists`。文件先写完并同步，再排他发布并同步目录；既有普通文件保留，符号链接/目录拒绝。发布后同步失败仍抛错，不能当作成功；不把凭据自动写入模板。例子见 [examples/configuration.rb](examples/configuration.rb)。

## 采集协议

`Collection.new(adapter:, options:, progress:, batch:, label:, report_error:, failure_code:, out:, error:, input:)` 返回一个可运行入口。options/progress 为工厂 callable；batch 是实现 `new(report:, progress:, requested:)`、`collect(device) { snapshot }` 与 `run(present:) { operation }` 的协作者，当前使用 `CtxRunner::Batch`。Collection 不加载 Runner，也不重复实现报告或取消状态机。

adapter 实现 `inventory(options, progress:) -> [targets, total]`、`prepare(targets, options) -> context`、`report(options)`、`execute(targets, options) { |target| ... }`、`collect(target, options, context:, progress:) -> snapshot`、`after_collect(report, options)`。execute 必须在返回前回收线程。预览在凭据和设备预检之前，所有预检在报告创建与连接之前。`run` 返回 0 完整、1 未完成/无目标、2 错误、130 取消。

Options 协作者沿用现有入口协议：`informational?`、`validate_interaction!`、`load_environment`、`initialize_files`、`missing?`、`load`、`config`、`flags`、`values`、`sources`、`public_values`。厂商命令、凭据映射、AP 租约、Fabric 检查、backup 成功策略保留在消费模块。详见 [迁移边界](docs/migration.md)。

## 开发与验证

```sh
bundle install
bundle exec rake
bundle exec rake build
ruby script/verify_package.rb pkg/ctx_cli-0.1.0.gem
```

默认任务包括 RSpec、RuboCop 和离线示例。安装验证在独立 GEM_HOME/GEM_PATH 下运行普通与最小 Bundler 应用，检查实际加载来源。CI 参照 ctx_parser 的固定 action 提交和候选制品校验；发布需另行明确授权。

消费仓库可用 `CTX_CLI_PATH=../ctx_cli bundle exec rake` 显式联调；普通入口须先安装候选包。不隐式探测相邻目录。baseline 只在 Gemfile 中为现有 coverage 脚本引入开发依赖，没有新增 baseline 命令或核心依赖。
