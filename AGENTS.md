# ctx_cli 开发指南

## 职责

独立宿主 CLI 基础库。范式参照 ctx_parser：普通 Ruby 对象、显式 require 和参数、中文注释、英文 RSpec/Changelog、RuboCop Omakase。最低 Ruby 3.4，开发 Ruby 4.0.6；兼容 net-connector 现有最低版本，不依赖 ctx_parser、ctx_runner、Rails 或连接器。

- Configuration：来源发现、隔离的 YAML/.env、来源路径与配置快照；宿主声明命名空间、允许的共享字段和路径政策。
- Initializer：私有临时文件、排他发布、文件/目录同步；领域验证与问答留在宿主。
- Router/Command/Options：命令分发、参数解析与公共参数分组；不引入通用工作流 DSL。
- Terminal/Input/Output：借用标准流、交互检查、精确确认、显式 JSON 与安全诊断。
- Review：离线 JSON 来源读取、全量预检后发布和安全错误映射；领域结构、身份及策略由 adapter 验证。
- Collection：终端入口的配置/预览/预检/执行顺序；通过 adapter 采集，Batch 协作者负责业务完成判定和收尾。

## 契约

- require 不读取用户配置、不改 ENV、不消费 stdin、不创建目录或网络连接。按能力加载不得依赖先加载根入口。
- 参数、默认值和配置按边界快照；不要冻结调用方容器或资源。循环和不透明对象拒绝进入纯数据快照。
- 数组替换，false/nil/缺失分开；配置来源相对路径不跟随后续 cwd 改变。只在宿主完成层级合并后验证领域值。
- 用显式分隔符，不依赖 `$;`、`$/`、`$,`。默认展示不展开配置、凭据、协作者及异常正文。
- 终端归调用方所有，不关闭注入的 IO；非 TTY 不自动读取 stdin，信息分支不执行领域动作。
- 文件 0600、新目录 0700、不覆盖既有目录项；发布后同步失败不能报告成功，清理失败不覆盖取消或原始异常。
- Collection 的 execute 返回前必须回收线程；批次事实由 Runner 保存，CLI 不重试或重放设备动作。
- 保留全部工作区已有改动；提交、推送、远程创建和发布按用户明确授权的范围执行。

## 验证

`bundle exec rake` 执行 RSpec、lint 和离线 examples；`bundle exec rake build` 构建；`ruby script/verify_package.rb pkg/ctx_cli-0.3.0.gem` 验证普通与 Bundler 最小安装。

消费仓库通过显式 `CTX_CLI_PATH=../ctx_cli` 联调，普通入口使用安装包；两种验证分别记录。测试优先复用消费端配置、取消、持久化故障及 PTY 用例。工作流参照 ctx_parser，Ruby 3.4/4.0.6 和 Linux/macOS；本地未运行的矩阵不得称为通过。
