# 消费模块接入边界

| 消费者 | 移交给 ctx_cli | 保留职责 |
| --- | --- | --- |
| net-connector Config | YAML/.env 发现、来源路径、数据快照 | net-connector.yml 分区、默认目录与环境变量 |
| backup/TFTP/topology | 公共参数组、终端检查/密码、配置排他发布 | Planner、备份回执、TFTP 核验、归档与成功策略 |
| VXLAN | 分发、公共参数、初始化、终端确认、离线输入输出、采集入口 | NX-OS 命令、Fabric、计划项/哈希验证、凭据及操作租约 |
| Wireless | 同上 | 平台、AP/LLDP、计划格式、凭据与 AP 会话 |
| baseline | 现有 script/coverage.rb 参数和输出边界 | 能力矩阵生成、--check、领域 API 与所有离线示例 |

ctx_runner 继续拥有采集/报告/执行的业务状态，net-connector Inventory 继续拥有筛选；ctx_cli 不反向加载二者。普通 Config 旧入口保留为宿主政策适配，无第二份配置发现实现。

ctx_cli 初始版本为 0.1.0。首次发布依赖顺序先 ctx_cli，再 net-connector 与 CLI 消费模块；ctx_runner 的依赖链仍按其原有约定。提交、远程创建和发布按用户明确授权的范围执行。

## 0.2.0 接口命名

- `CtxCli::Initialization` / `ctx_cli/initialization` 改为 `CtxCli::Initializer` / `ctx_cli/initializer`，仅负责模板安全发布。
- `CtxCli::Application` / `ctx_cli/application` 改为 `CtxCli::Router` / `ctx_cli/router`，仅负责全局信息和子命令分发。

旧常量和 require 路径不保留别名。宿主需同步修改引用，并将 ctx_cli 依赖更新为 `~> 0.2.0`。`create`、`existing?`、`run` 的结果约定不变；初始化参数询问和厂商语义不迁入这两个对象。0.2.0 当前为本地候选，尚未发布。
