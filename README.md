# my-ShQveL

用于复现 ShQveL 在线学习与 fuzzing 实验的 Harness。目前包含 PostgreSQL 18.3、MySQL 8.4.8 和 MariaDB 12.2.2 三套已验证流程，并包含 TiDB 8.5.5 的隔离 Harness 准备代码，以及本项目使用的 SQLancer++/ShQveL 源码快照。

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
mariadb/                             本机构建后产生；不入 Git
tidb/                                本机构建后产生；不入 Git
state/, spool/, logs/, validation/   运行产物；不入 Git
```

Harness 不会管理目录外的数据库实例。PostgreSQL 使用端口 `55433`，MySQL 使用端口 `3308`，MariaDB 使用端口 `3310`，TiDB 计划使用 SQL 端口 `4010` 和 status 端口 `10181`；脚本会核对 PID、可执行文件和数据目录，避免误操作系统中已有的实例。

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
/app/nfs/chq_data/ShQveL/mariadb/<run-id>
/app/nfs/chq_data/ShQveL/tidb/<run-id>
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

## MariaDB 12.2.2

MariaDB 的源码、build、install、data、socket 和 PID 均位于 `mariadb/`，不会复用或停止系统中的 MySQL/MariaDB。构建及正式入口：

```bash
scripts/build_mariadb_cov.sh
scripts/preflight_mariadb_cov.sh
scripts/run_mariadb_24h.sh
```

正式入口固定运行 24 个 3600 秒 epoch，使用端口 `3310`，结果写到 `/app/nfs/chq_data/ShQveL/mariadb/<run-id>`。每个 epoch 会短暂停止专属 MariaDB 以刷新 gcov counter，冻结累计 coverage 后立即重启；raw trace 的处理和 NFS 上传期间 ShQveL 继续 fuzzing。MariaDB general log 同时保存原始压缩日志和 `replay.sql.gz`，后者允许预期的无效 fuzz SQL 在 `mariadb --force` 下继续重放。

用于 Harness 验证的可变时长入口为：

```bash
SHQVEL_RUN_ID=my-probe scripts/run_mariadb_experiment.sh 2 180
```

多 epoch 短测要求单个 epoch 至少 180 秒，避免 lcov 后处理耗尽下一段测试预算；正式的 3600 秒设置不受影响。官方文档目录位于 `work/SQLancerPlusPlus/dbconfigs/mariadb-url-12.2.yml`。

正式入口还要求最近七天内的双 epoch readiness 证书。证书会核对 NFS 上的 COMPLETE、SHA-256、LLM/token 记录、服务端 SQL 数量和累计覆盖率单调性：

```bash
scripts/certify_mariadb_readiness.py \
  --run /app/nfs/chq_data/ShQveL/mariadb/<validation-run> \
  --server /app/my_ShQveL/mariadb/install/bin/mariadbd \
  --output /app/my_ShQveL/state/mariadb-readiness.json
scripts/preflight_mariadb_cov.sh --require-probe
```

在专属 MariaDB 已启动时，可以重放某个 epoch。脚本默认允许无效 fuzz SQL继续执行、丢弃普通查询输出、限制单语句时间，并通过数据库内的 EOF marker 证明输入确实执行到末尾：

```bash
scripts/replay_mariadb_sql.sh \
  /app/nfs/chq_data/ShQveL/mariadb/<run-id>/epoch-01/sql/replay.sql.gz \
  validation/my-replay
```

## TiDB 8.5.5

> 当前状态：Harness 已完成静态检查和 Go coverage 微型语义验证，但尚未完成真实 TiDB 构建、在线学习探针和双 epoch 动态验证。原因是准备期间 MariaDB 24 小时正式实验正在占用该机器；TiDB 入口中的资源互斥门会拒绝并发构建或启动，避免污染 MariaDB 实验结果。迁移到其他空闲容器后，应从下文“接续验证清单”继续，不要直接启动 24 小时实验。

TiDB 使用 Go 原生 coverage，而不是 gcov。专属源码、Go toolchain、build cache、安装、data 和 `GOCOVERDIR` 均位于 `/app/my_ShQveL/tidb/`，不会复用 `/app/dbms` 或系统 TiDB；运行使用 SQL 端口 `4010` 和 status 端口 `10181`。主要路径如下：

```text
/app/my_ShQveL/tidb/source             TiDB v8.5.5 源码
/app/my_ShQveL/tidb/toolchain/go       固定 Go 1.25.5 toolchain
/app/my_ShQveL/tidb/install            coverage 插桩后的 tidb-server
/app/my_ShQveL/tidb/data               独立 unistore 数据
/app/my_ShQveL/tidb/coverage-runtime   累计 GOCOVERDIR
/app/my_ShQveL/tidb/logs               构建和服务日志
/app/nfs/chq_data/ShQveL/tidb          每小时及最终实验结果
```

构建和基础预检入口：

```bash
scripts/build_tidb_cov.sh
scripts/preflight_tidb_cov.sh
```

构建固定使用 `v8.5.5` tag 和 `go build -cover -covermode=atomic -coverpkg=./...`。每个 epoch 边界会暂停 ShQveL，向经过 PID 和 executable 校验的 TiDB 发送 `SIGTERM`，等待 TiDB 自身 signal handler 完成 graceful shutdown 和 Go counter 刷新，冻结原始 covdata后重启。这里不能使用 `kill -9`；TiDB v8.5.5 也没有参考脚本假设的 `POST /shutdown` 路由。

结果设计为同时保存：

- TiDB 独立 general log 和普通 server log；
- SQLancer 逐条 SQL、执行时间和运行日志；
- Python/Java LLM 事件、token 用量和 learned-fragment checkpoint；
- 原始 `covdata.raw.tar.gz`、合并后 covdata、`raw.out(.gz)`、package summary 和 function summary；
- SHA-256 清单、epoch `COMPLETE`、final artifacts 和 NFS 顶层 `COMPLETE`。

已完成、不需要重复的检查：

- `bash -n scripts/*tidb*.sh` 和 `git diff --check`；
- 9 个 PingCAP v8.5 官方文档 URL 的 HTTP 200 验证；
- `tidb-url-8.5.yml` 在 `shqvel` conda 环境中的 YAML 解析；
- 小型 Go 程序连续两次运行并通过 SIGTERM 正常返回，证明同一 `GOCOVERDIR` 的多个 counter 可累计合并；
- `go tool covdata merge/textfmt/percent` 和 `go tool cover -func`，输出为 `mode: atomic`；
- build/start/run 在 MariaDB runner 存活时确实拒绝执行；
- TiDB 脚本中不存在全局 `pkill`、`fuser -k`、`/tmp/tidb` 或 `/app/dbms` 操作。

为避免影响正在执行的 MariaDB 正式实验，TiDB 的 build/start/run 入口包含资源互斥门：检测到 `/app/my_ShQveL/scripts/run_mariadb_experiment.sh` 存活时会直接拒绝。完成动态覆盖率和双 epoch 验证后，正式入口为：

```bash
scripts/run_tidb_24h.sh
```

在动态验证完成之前，不应把当前 TiDB Harness 标记为 24 小时实验就绪。

### 在其他容器中接续 TiDB 验证

仓库目前固定部署在 `/app/my_ShQveL`。新容器中先准备 conda/Java/Maven、NFS 和不含密钥的代码仓库，再在仓库外创建 `llm.properties` 并链接到 `work/SQLancerPlusPlus/dbconfigs/llm.properties`。禁止把配置内容或 API Key 提交到 Git。

按以下顺序接续：

1. 确认没有 `run_mariadb_experiment.sh`，端口 `4010/10181` 空闲，且本地至少保留 10 GB、NFS 至少保留 20 GB。
2. 执行 `scripts/build_tidb_cov.sh`；核对源码 tag、binary SHA-256、Go 版本以及 `state/tidb-cov-build-manifest.json`。
3. 执行 `scripts/start_tidb_cov.sh`，验证 PID 对应 `/app/my_ShQveL/tidb/install/bin/tidb-server`、`SELECT VERSION()` 返回 TiDB、status API 可用，并确认 general log 实际记录 SQL。
4. 用 `scripts/stop_tidb_cov.sh` 优雅停止，确认 `coverage-runtime` 中同时存在 `covmeta.*` 和 `covcounters.*`；然后依次测试 freeze 和 collect 脚本，确保 `raw.out` 非空且为 atomic mode。
5. 根据真实 general-log 样本补充 TiDB 专用 SQL 提取/重放脚本。当前 `analyze_mysql_epoch.py` 只临时承担通用运行和 LLM 指标汇总，不能当作 TiDB 服务端 SQL 完整性证明。
6. 做一次短 SQLancer 连接 smoke，再做在线学习探针，要求至少一个 LLM 请求成功、有 token 记录，并有 fragment 经 TiDB 直接验证后进入 checkpoint。
7. 跑至少两个 epoch 的短实验，验证第二个 epoch 的 coverage hit 不回退、coverage denominator 不变化、两个 epoch 及 final artifacts 的 checksum/`COMPLETE` 均可在 NFS 上校验。
8. 仿照 MariaDB 增加 TiDB readiness certificate，让 `preflight_tidb_cov.sh --require-probe` 校验最近的双 epoch 结果，并让 `run_tidb_24h.sh` 强制要求该证书。完成这一步后才能解除“未就绪”状态并正式运行 24×3600 秒。

短测可以使用可变时长入口，例如：

```bash
SHQVEL_RUN_ID=tidb-probe scripts/run_tidb_experiment.sh 2 180
```

但当前脚本尚未像 MariaDB 一样强制最小 epoch 时长；短测时应让 epoch 足够长，避免 coverage 后处理时间掩盖实际 fuzzing 时间。正式运行入口仍为固定的 `scripts/run_tidb_24h.sh`。

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
