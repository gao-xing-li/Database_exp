# 第 7–9 周 Web 应用

Flask + SQL Server 的单店现货经营工作台。已实现登录、商品 CRUD、库存查询与增减调整、现货草稿订单及明细增改删、结账与取消、顾客本人订单查询、四类角色权限、统一错误和日志。

真实 SQL Server 集成测试及浏览器流程的执行结果见[验证记录](03_测试与验证记录.md)。本目录基于第六周最终结构，保留原 15 张业务表，新增 1 张认证技术表 `WebUser`、2 个 Sequence、5 个应用数据库角色和顾客订单 RLS。完整预售、采购验收和会员资料维护界面暂未实现。

## 阅读入口

- [设计与决策](../第7-9周%20设计与决策.md)，[架构与接口](01_架构与接口.md)。
- [操作手册](02_操作手册.md)，[测试与验证](03_测试与验证记录.md)。
- [第二阶段报告草稿](../第二阶段报告_草稿.md)，[分工说明](04_第二阶段分工.md)，[ai_log](ai_log.md)。
- [恢复的课程任务原文](任务原文_聊天恢复.txt)，[第六周结构字典](../第六周业务产出/02_重构方案与数据字典.md)。

## 从空环境启动

要求 Python 3.12、可运行 SQL Server 2022 的 x86-64 系统。SQL Server 可以是本机独立 Developer 实例，或本目录 Compose 容器。浏览器使用支持 `dialog` 和 `fetch` 的现代版本。本次实际版本记录在 [environment.json](results/environment.json)。

在仓库根目录建立虚拟环境。

```bash
python3 -m venv .venv
source .venv/bin/activate
cd 第7-9周业务产出
pip install -r requirements.txt
```

在当前终端设置 `DB_ADMIN_PASSWORD` 和 `COURSE_DEMO_PASSWORD`。前者须满足 SQL Server 密码策略，后者至少 12 位，初始化的五个演示账号使用该密码。Linux Bash 可用隐藏输入，避免写入口令历史。

```bash
read -rsp 'SQL 管理密码: ' DB_ADMIN_PASSWORD
export DB_ADMIN_PASSWORD
read -rsp '演示 Web 密码: ' COURSE_DEMO_PASSWORD
export COURSE_DEMO_PASSWORD
docker compose up -d
docker compose logs sqlserver
```

等 SQL Server 日志出现 `SQL Server is now ready for client connections` 后执行。

```bash
python scripts/init_demo.py
python run.py
```

在运行应用的机器浏览器打开 `http://127.0.0.1:5000`。云端执行器的回环地址只属于云端机器，不是本机 Windows 地址。需要本机操作时，把仓库复制到本机后按上述说明启动，或使用环境支持的端口转发。

Windows PowerShell 的虚拟环境激活为 `.\.venv\Scripts\Activate.ps1`，Python 命令可用 `python`。环境变量使用 `$env:DB_ADMIN_PASSWORD`、`$env:COURSE_DEMO_PASSWORD`，可通过 `Read-Host -AsSecureString` 读取后经 `System.Net.NetworkCredential` 的 `Password` 属性赋值。其余 Python 和 Compose 命令相同。Windows 原生 SQL Server 不需要 Compose，启动前另设 `DB_SERVER`、`DB_PORT`、`DB_ADMIN_USER`，默认分别为 `127.0.0.1`、`14333`、`sa`。

初始化专门使用 `AnimeGoodsStoreDB_Week6App`。顺序为原 01–07 的改库名执行文本，第六周 `migration.sql`，`sql/01_web_security.sql`，序列和受限账户。原始 SQL 01–05 用 GB18030 解码，06–07 和新增文件用 UTF-8。没有修改原始文件，没有连接 Windows 旧实验库。脚本遇到已有库或已有配置会停止，不自动清空数据库。

成功后生成被 Git 忽略的 `config.local.json`，包含随机会话密钥和五个受限 SQL 登录。Web 不使用 sa。可以用环境变量 `COURSE_CONFIG` 指向其他位置的同类配置，具体字段参见 `config.example.json`。演示数据库登录名和 `course_customer` 的 RLS 绑定一致，不要只改配置用户名而遗漏数据库安全策略。认证账户仅在初始化时生成，演示用户名为 `manager`、`clerk`、`inventory`、`customer1`、`customer2`。

再次启动仅运行 `python run.py`。重启容器可运行 `docker compose start`，保留对应卷和本地配置。不要为重新启动而删除卷或重跑原 01。初始化中途失败时保留现场，核对报错及对象，不要在已有业务库上尝试重建。若要从头演示，另建一个空 SQL 实例，保留原实例和配置。

## 运行测试

忘记网页密码时，先按[操作手册的密码重设步骤](02_操作手册.md)生成本地 SQL 并在 SSMS 执行，无需重新初始化数据库。SSMS、本机 SQL Server 与截图复现的关系，也见操作手册。本地改 `COURSE_DEMO_PASSWORD` 只影响下一次初始化的输入，不会修改已有账户。

数据库和 `config.local.json` 准备好后，在相同虚拟环境设置初始化时的 `COURSE_DEMO_PASSWORD`。

```bash
python -m pytest -q --junitxml=results/pytest.xml
python scripts/export_evidence.py
```

测试只接受专用样例库，生成独立测试商品和订单，结束后清理这些记录，保留原始 6 件商品、6 笔订单及库存。Sequence 消耗的编号不回退。不要在有并行演示操作时运行测试，测试拥有清理其自身数据所需的管理角色权限。

可选浏览器测试，先保持 `run.py` 运行，另开同环境终端。

```bash
pip install -r requirements-browser.txt
python -m playwright install chromium
python scripts/browser_smoke.py
```

在首次安装 Chromium 提示缺少系统库时，按 Playwright 对应操作系统的安装提示补齐。浏览器脚本输出 `results/browser.json` 和 8 张角色流程截图，也会清理自身创建的演示商品和订单。设置自定义浏览器缓存目录时，安装和运行使用相同 `PLAYWRIGHT_BROWSERS_PATH`。

## 目录与层级

```text
app/templates/index.html    页面结构和表单
app/static/app.js          页面 API 调用和反馈
app/static/style.css       桌面及移动布局
app/__init__.py            HTTP 路由、会话、CSRF、响应和异常处理
app/services.py            业务规则、权限、事务边界
app/db.py                  连接、提交、回滚、释放
app/repository.py          参数化 SQL，唯一运行时 SQL 入口
sql/01_web_security.sql    认证表、应用角色、数据库行级过滤
scripts/init_demo.py       独立样例环境初始化，不是生产数据迁移
tests/                     真实 SQL Server 集成测试
scripts/browser_smoke.py   实际浏览器角色流程
results/                   可提交的测试结果、截图和业务值
```

日志 `results/app.local.jsonl` 和本地配置不提交。日志记录请求标识、时间、操作、角色、错误码和结果，详细异常留在后端。用户只看到统一简短提示和请求标识。

本版本是本机课程演示版本。未验证公网部署、生产证书、多实例会话、限流、支付网关或生产运维。对外部署时需独立配置 HTTPS、`cookie_secure`、账户及持久日志，并核对驱动的加密连接设置。
