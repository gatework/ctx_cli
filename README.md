# ctx_cli

可组合的 Ruby 命令行基础库，用于减少网络自动化模块的入口样板代码。它处理配置、终端和入口流程，领域模块继续拥有厂商语法、业务校验、清单选择及设备能力。

## 公共能力

| 对象 | 职责 |
| --- | --- |
| `Router` | 惰性子命令分发、全局帮助/版本、返回退出码 |
| `Command` / `Options` | 每次独立的参数快照、信息分支、公共 OptionParser 分组 |
| `Configuration` | 多层文件发现、隔离环境、来源路径、纯数据快照 |
| `Initializer` | 私有文件排他创建、同步、保留已有配置 |
| `Terminal` | 真实终端检查、问答、隐藏密码、完整 token 确认 |
| `Input` / `Output` | 文件/stdin、显式 JSON、仅含错误类型的诊断 |
| `Review` | 离线来源读取、全量预检后发布、安全诊断与退出码映射 |
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

`sources["fields"]` 使用 JSON Pointer 作为字段键，例如 `/parallel`、`/ssh/known_hosts`。字面键 `a.b` 对应 `/a.b`，嵌套 `a → b` 对应 `/a/b`；键内 `/` 编为 `~1`、`~` 编为 `~0`。数组作为整体字段记录来源。宿主的 `path_fields` 声明语法不变，来源索引不保留点分键别名。

默认依次搜索 `/etc/<namespace>`、`/usr/local/etc/<namespace>`、`$XDG_CONFIG_HOME/<namespace>`（否则 `~/.config/<namespace>`）、入口目录和启动目录。每层读取 `<namespace>.yml` 与 `<name>.yml`，显式文件最后。共享文件按 `common` 和工具名称分区；name 与 namespace 相同时使用普通独立文件。`directories:` 可以完整替换搜索范围。

宿主把各层公共环境值转换成领域字段后，通过 `Configuration.merge(defaults, dotenv_values, yaml, process_values, cli)` 实现 CLI > 进程环境 > YAML > .env > 默认值。数组整层替换，false/nil 保留。相对路径按来源目录解释；支持 `path_literals:`（如 `system`）和 URI。`load` 重复调用不重新读文件。

`Initializer#create(path:, contents:)` 返回 `:created` 或 `:exists`。文件先写完并同步，再排他发布并同步目录；既有普通文件保留，符号链接/目录拒绝。发布后同步失败仍抛错，不能当作成功；不把凭据自动写入模板。例子见 [examples/configuration.rb](examples/configuration.rb)。

## 采集协议

`Collection.new(adapter:, options:, progress:, batch:, label:, report_error:, failure_code:, out:, error:, input:)` 返回一个可运行入口。options/progress 为工厂 callable；batch 是实现 `new(report:, progress:, requested:)`、`collect(device) { snapshot }` 与 `run(present:) { operation }` 的协作者，当前使用 `CtxRunner::Batch`。Collection 不加载 Runner，也不重复实现报告或取消状态机。

adapter 实现 `inventory(options, progress:) -> [targets, total]`、`prepare(targets, options) -> context`、`report(options)`、`execute(targets, options) { |target| ... }`、`collect(target, options, context:, progress:) -> snapshot`、`after_collect(report, options)`。execute 必须在返回前回收线程。预览在凭据和设备预检之前，所有预检在报告创建与连接之前。`run` 返回 0 完整、1 未完成/无目标、2 错误、130 取消。

Options 协作者沿用现有入口协议：`informational?`、`validate_interaction!`、`load_environment`、`initialize_files`、`missing?`、`load`、`config`、`flags`、`values`、`sources`、`public_values`。厂商命令、凭据映射、AP 租约、Fabric 检查、backup 成功策略保留在消费模块。详见 [迁移边界](docs/migration.md)。

## 开发与验证

```sh
bundle install
bundle exec rake
bundle exec rake build
ruby script/verify_package.rb pkg/ctx_cli-0.4.0.gem
```

默认任务包括 RSpec、RuboCop 和离线示例。安装验证在独立 GEM_HOME/GEM_PATH 下运行普通与最小 Bundler 应用，检查实际加载来源。CI 参照 ctx_parser 的固定 action 提交和候选制品校验；发布需另行明确授权。

消费仓库可用 `CTX_CLI_PATH=../ctx_cli bundle exec rake` 显式联调；普通入口须先安装候选包。不隐式探测相邻目录。baseline 只在 Gemfile 中为现有 coverage 脚本引入开发依赖，没有新增 baseline 命令或核心依赖。

Input reads default to a 16 MiB byte budget (`CtxCli::Input.read(max_bytes:)`). Configuration data is limited to 128 nesting levels and 100,000 nodes; oversized input raises `ArgumentError` before recursive deserialization.

## 离线 review 入口

`CtxCli::Review` 接收 `command:`（`CtxCli::Command`）、`directory:`（批次内证据目录名）和 `adapter:`。入口先处理帮助，再按文件名顺序读取 JSON，通过 `Input` 限制单个文件大小，最后依次调用：

- `adapter.prepare(sources, options)`：验证全部领域记录、身份及策略并返回上下文，不创建输出。每条来源为 `[path, body, document]`；领域适配器可在本次入口拥有的来源数组中附加建议。
- `adapter.publish(sources, options, batch:, context:)`：创建报告并返回完成提示。发布及持久性状态仍由领域模块和 Runner 管理。

失败只输出异常类型，返回 2；中断返回 130；诊断流失败不覆盖原始退出码。帮助不加载证据或调用适配器。此类不读取凭据、连接设备或判断业务健康。默认单文件 16 MiB、批次原始正文总计 64 MiB、文件数 10000；宿主可通过 `max_bytes:`、`max_total_bytes:`、`max_files:` 调整。JSON 默认嵌套限制保持开启；上述限制不是进程 RSS 的精确上限。

`Collection` 对普通参数/依赖异常只显示类型；宿主需要公开操作提示时使用 `CtxCli::Collection::Error`，其正文必须由宿主构造，不得直接包装外部异常正文、凭据或设备回显。该类型继承 ArgumentError，既有库调用方仍可按参数错误捕获。

`CtxCli::Apply` 负责版本计划的校验和、`--item` 选择、终端确认及退出码；通过 `adapter:` 和 `execution:` 注入领域校验、凭据、会话、日志及执行器。ctx_cli 不依赖 ctx_runner 或连接器。

## Domain contract migration (2026-10-30)

Use `target` in controlled apply documents and accept JSON nesting up to the shared 128-level evidence budget. Host adapters must use schema 4 plans. See the [schema 4 migration and module contracts](https://github.com/gatework/ctx_runner/blob/main/docs/contracts-2026-10-30.md). Regenerate old collection reports and change plans; changing only their version number is not supported.
