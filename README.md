# my-ShQveL

用于复现 ShQveL 在线学习与 fuzzing 实验的 Harness。目前包含 PostgreSQL 18.3 和 MySQL 8.4.8 两套隔离、带 gcov 覆盖率的 24 小时实验流程，以及本项目使用的 SQLancer++/ShQveL 源码快照。

本仓库只保存可复用的脚本、源码修改、文档 URL 和配置模板，不保存 API Key、数据库源码/编译/安装/数据目录、运行状态、SQL 日志、覆盖率文件或实验结果。实验结果默认同步到 NFS，不能把 Git 仓库当作结果存储。

## 目录结构

```text
config/experiment.env.example        PostgreSQL/Harness 配置模板
scripts/                             构建、预检、运行、采集、上传和重放脚本
work/SQLancerPlusPlus/               ShQveL 所用 SQLancer++ 源码快照
  dbconfigs/*-url*.yml               LLM 学习使用的官方文档目录
  dbconfigs/llm.properties.example   LLM 配置格式（无密钥）
  docs/ShQveL-local-modifications.md  相对原版 ShQveL 的修改记录
postgres/                            本机构建后产生；不入 Git
mysql/                               本机构建后产生；不入 Git
state/, spool/, logs/, validation/   运行产物；不入 Git
```

Harness 不会管理目录外的数据库实例。PostgreSQL 使用端口 `55433`，MySQL 使用端口 `3308`；脚本会核对 PID、可执行文件和数据目录，避免误操作系统中已有的实例。

## 环境要求

当前脚本面向 Debian/Ubuntu Linux，主要依赖：

- Bash、Python 3、Java、Maven、Conda；
- `gcc/g++`、`make`、`cmake`、`bison`、`flex` 和 DBMS 编译依赖；
- `lcov`、`gcov`、`genhtml`、`rsync`、`zstd`、`curl`、`sudo`；
- 本机 `postgres` 系统用户（PostgreSQL 构建与运行使用）；
- 可写的 NFS 结果目录。

SQLancer++ 的 Python 依赖见 [`work/SQLancerPlusPlus/requirements.txt`](work/SQLancerPlusPlus/requirements.txt)。建议建立独立环境：

```bash
conda create -n shqvel python=3.11 -y
conda activate shqvel
pip install -r work/SQLancerPlusPlus/requirements.txt
cd work/SQLancerPlusPlus
mvn -DskipTests package
```

## 私密配置

不要把真实配置放进仓库。复制示例到仓库外部并填写：

```bash
mkdir -p /tmp/SQLancerPlusPlus/dbconfigs
cp work/SQLancerPlusPlus/dbconfigs/llm.properties.example \
  /tmp/SQLancerPlusPlus/dbconfigs/llm.properties
chmod 600 /tmp/SQLancerPlusPlus/dbconfigs/llm.properties
ln -sfn /tmp/SQLancerPlusPlus/dbconfigs/llm.properties \
  work/SQLancerPlusPlus/dbconfigs/llm.properties
```

`llm.properties` 支持的字段以示例文件为准，包括 `api_key`、`base_url` 和模型名。`.gitignore` 会排除真实文件，但提交前仍应运行本文末尾的审计命令。

PostgreSQL 的非密钥实验参数可这样准备：

```bash
cp config/experiment.env.example config/experiment.env
```

如果仓库不在 `/app/my_ShQveL`，需同步修改环境文件路径。目前 MySQL Harness 的隔离路径固定为 `/app/my_ShQveL`，跨路径部署前应先参数化 `scripts/mysql_common.sh`。

## NFS 结果目录

默认目标是：

```text
/app/nfs/chq_data/ShQveL/postgres/<run-id>
/app/nfs/chq_data/ShQveL/mysql/<run-id>
```

示例挂载（由管理员按实际环境执行）：

```bash
mkdir -p /app/nfs/chq_data
mount -t nfs -o vers=3,rsize=1048576,wsize=1048576,async,noatime,nodiratime \
  10.26.43.20:/volume1/chq_data /app/nfs/chq_data
```

每个小时是一个 epoch。上传采用临时目录、SHA-256 校验和 `COMPLETE` 标记；只有远端校验成功才清理相应本地临时数据。每个 epoch 保存 SQL/服务端审计日志、学习事件、成功率统计及累计覆盖率原始 trace，便于重放和重新统计。

## PostgreSQL 18.3

构建脚本会下载源码，在 `postgres/` 下编译并初始化独立的覆盖率实例：

```bash
scripts/build_postgres_cov.sh
scripts/prepare_shqvel_workdir.sh
scripts/preflight.sh
scripts/run_24h.sh
```

`preflight.sh` 必须输出 `READY_FOR_24H=YES` 后才能正式运行。`run_24h.sh` 固定执行 24 个 3600 秒 epoch，采用 ShQveL 原始思想中的“在线学习 + fuzzing”模式。结束时会优雅停止 PostgreSQL 以刷新 gcov 计数，采集最终覆盖率，再恢复专用实例供重放使用。

重建可读 SQL 与结构化执行记录：

```bash
scripts/finalize_replay.sh RUN_ID
```

## MySQL 8.4.8

MySQL 构建脚本要求源码已解压到 `mysql/source`，并且 Boost 位于源码要求的位置。源码、编译树、安装目录和数据目录全部在 `mysql/` 下，不使用系统已有 MySQL：

```bash
# 先将 MySQL 8.4.8 源码准备为 /app/my_ShQveL/mysql/source
scripts/build_mysql_cov.sh
scripts/preflight_mysql_cov.sh
scripts/probe_mysql_cov.sh
scripts/preflight_mysql_cov.sh --require-probe
scripts/run_mysql_24h.sh
```

短探针必须同时证明：专用 mysqld 含 gcov 插桩、ShQveL SQL 确实在该实例执行、停止后 `.gcda` 被刷新、lcov trace 非空、LLM 至少成功返回一次且至少一个 learned fragment 通过目标 DBMS 的直接验证。正式运行入口不接受时长参数，固定执行 24 小时。

每小时边界会暂停 ShQveL、优雅停止专用 MySQL 刷新计数、冻结累计覆盖率、重启 MySQL，再恢复 ShQveL；覆盖率后处理与下一 epoch 并行。MySQL general log 是 SQL 重放依据，ShQveL 自身统计是语句成功率依据。

## 扩展其他 DBMS

建议按以下边界新增实现，不要把新 DBMS 的部署产物提交到 Git：

1. 在 `work/SQLancerPlusPlus/dbconfigs/` 添加官方文档 URL YAML，并在独立子目录放置 `disabled_options.csv`、类型配置等非私密元数据。
2. 确认 SQLancer++ general provider/JDBC 能连接该 DBMS，先做短时在线学习探针。
3. 新建 `<dbms>_common.sh`，固定 Harness 自有的源码、安装、数据、端口和 PID 身份检查。
4. 实现 build/start/stop/reset/collect/preflight 脚本；覆盖率采集必须针对 Harness 自己构建的可执行文件，并验证 raw trace 非空。
5. 实现每小时 snapshot/upload：至少保存可完整重放的 SQL、DDL、执行结果、LLM 原始事件与 token 用量、learned sketch/checkpoint、成功率、DBMS 日志、`raw.info` 和校验清单。
6. 先跑短 probe 和 2-epoch 测试，验证进程重启、覆盖率单调性、NFS 原子上传、断点恢复及磁盘空间上限，再开放固定 24 小时入口。

不要仅凭端口可连接就认定目标正确；应像现有脚本一样核对进程可执行文件、安装路径、数据目录、版本和构建哈希。

## 结果完整性与重放

正式结果以 NFS 顶层 `COMPLETE`、24 个 epoch 的 `COMPLETE`、final coverage 和校验和均成功为完成条件。不要只看 runner 进程退出或 epoch 数量。PostgreSQL CSV audit log / MySQL general log 保存数据库实际接收的 SQL；重放时应使用全新的隔离数据库，并允许预期的无效 SQL 继续执行。

## 提交前安全审计

```bash
git status --short
git ls-files
git grep -nEi '(api[_-]?key|authorization|bearer|secret|token)[[:space:]]*[:=]' \
  -- ':!*.example' ':!README.md'
git check-ignore -v config/experiment.env \
  work/SQLancerPlusPlus/dbconfigs/llm.properties \
  mysql/data postgres/data state spool logs validation
```

还应检查大文件，避免误提交数据库或覆盖率产物：

```bash
git ls-files -z | xargs -0 -r du -k | sort -n | tail -20
```

## 上游与说明

- ShQveL 论文：<https://arxiv.org/abs/2505.02012>
- SQLancer++：<https://github.com/suyZhong/SQLancerPlusPlus>
- 本地逻辑修改说明：[`work/SQLancerPlusPlus/docs/ShQveL-local-modifications.md`](work/SQLancerPlusPlus/docs/ShQveL-local-modifications.md)

本仓库包含研究原型。开始长时间实验前，务必完成目标身份、LLM 学习、覆盖率与 NFS 写入四类预检。
