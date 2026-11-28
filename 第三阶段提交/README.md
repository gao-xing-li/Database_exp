# 第 10–13 周数据库编程与事务处理

本目录包含 B 负责的库存与补货实现、独立测试、并发交接和报告草稿。完整 v2.0 按第 13 周要求汇合 A 的销售与订单 SQL、窗口查询和双会话实测证据。

| 要找的内容 | 入口 |
|---|---|
| 库存调整、警戒值、补货量 | [procedure.sql](代码/procedure.sql) · [function.sql](代码/function.sql) |
| 库存流水表与触发器 | [inventory_schema.sql](代码/inventory_schema.sql) · [trigger.sql](代码/trigger.sql) |
| 补货验收、分类递归 | [restock_transaction.sql](代码/restock_transaction.sql) · [recursive_query.sql](代码/recursive_query.sql) |
| 第 13 周共用基线、来源字段与并发交接 | [设计与交接](设计与交接.md) · [baseline.sql](测试/baseline.sql) · [hold_restock.sql](测试/hold_restock.sql) |
| 验证状态与报告 | [结果记录](结果/README.md) · [报告源码](报告/main.tex) · [AI 使用记录](ai_log.md) |

## 准备第三阶段样例库

在仓库根目录使用已有 Python 3.12 环境和 SQL Server。Windows 本机需要已能以 Windows 身份连接 SQL Server，并装有 [应用的 Windows 依赖](../第7-9周业务产出/requirements-windows.txt)。下面以端口 1433 为例。端口、安装和 SQL 登录方式见[第二阶段运行说明](../第二阶段提交/第7-9周_Web应用与集成测试/README.md)。

```powershell
$env:DB_ADMIN_TRUSTED = '1'
$env:DB_PORT = '1433'
$stage3 = (Resolve-Path '.\第三阶段提交').Path
$env:COURSE_CONFIG = Join-Path $stage3 'config.local.json'
$demoPassword = Read-Host '设置第三阶段演示密码，至少12位' -AsSecureString
$env:COURSE_DEMO_PASSWORD = [System.Net.NetworkCredential]::new('', $demoPassword).Password
python '.\第三阶段提交\prepare_stage3.py'
```

初始化创建 `AnimeGoodsStoreDB_Week6App_Stage3`。脚本按原 01–07、第六周迁移、Web 认证结构、第三阶段库存对象和 Web 账号的顺序执行。第三阶段使用 `course_stage3_` SQL 登录前缀。这套连接配置的 `inventory_v2` 为 `true`，应用据此选择库存存储过程和表单。

如果已有第三阶段库和配置，直接设好 `COURSE_CONFIG` 并启动。初始化遇到同名库、配置或登录会停止。安装新版本对象时在专用数据库中单独执行相应的 `CREATE OR ALTER` 脚本。

```powershell
python '.\第7-9周业务产出\run.py'
```

浏览器打开 [经营工作台](http://127.0.0.1:5000/)，用 `inventory` 或 `manager` 和刚设置的演示密码登录。从库存页选商品并填写增减量、原因和警戒值。点击「确认调整」后核对页面库存、建议补货量和数据库流水。只需改警戒值时填新值并点击「仅更新警戒值」。补货验收通过 SQL 入口演示。

## SQL 入口与验收

在 SSMS 中选择同一第三阶段库，并在不同会话间检查所选库名。先运行 `测试/baseline.sql`，每次改变 P/Q 或补货单状态的用例组之前重置一次。A 的草稿订单由销售侧脚本单独重置。

```sql
EXEC dbo.AdjustInventory
    @product_id = 90001301, @delta = -2, @reason = N'盘点少了两件', @employee_id = 2;
SELECT dbo.RestockQuantity(90001301, DEFAULT) AS suggested_quantity;

-- 重置基线后演示验收与分类子树。
EXEC dbo.ReceiveRestock @purchase_id = 90013101, @employee_id = 2;
EXEC dbo.ListCategorySubtree @category_id = 90001201;
```

| 用例组 | 执行脚本 | 通过判定 |
|---|---|---|
| 第 10–11 周库存 | [10_11_inventory_checks.sql](测试/10_11_inventory_checks.sql) | 正常与异常参数、补货量、单行和批量前后值、来源、回滚断言全部通过 |
| 第 12 周补货 | [12_restock_checks.sql](测试/12_restock_checks.sql) | 提交、重复拒绝、第二项库存超限回滚、修正后重试分别核对库存、验收和流水 |
| 第 12 周分类 | [12_category_checks.sql](测试/12_category_checks.sql) | 根、中间、叶和不存在编号分别返回 5、2、1、0 行，层级及路径符合样例 |
| Web 调用回归 | [test_web_inventory.py](测试/test_web_inventory.py) | 核对 Flask 路由传给 SQL 的员工和参数、角色权限、错误映射与 v1.0 兼容 |

SQL 断言脚本末尾输出 `PASS` 才算通过。将各查询窗口的实际结果保存到[结果目录](结果/README.md)。在专用副本内，用 `hold_restock.sql` 的 B1 完成入库写入并保留事务，再按 B2 在原会话提交或回滚。第 13 周的订单会话、锁与隔离级别实验由 A 的脚本接续。

```powershell
python -m pytest -q '第三阶段提交/测试/test_web_inventory.py' '第7-9周业务产出/tests/test_password_reset.py'
```

## v2.0 合并核对

- 把销售过程、函数和订单触发器加入现有的 `procedure.sql`、`function.sql`、`trigger.sql`。补充 `window_query.sql`、`order_transaction.sql`、双会话脚本及实测结果。
- 日常 Web 源码在 `第7-9周业务产出`。A 的 SQL 结账调用就位后，在该位置替换过渡结账，在安装顺序中加入订单事务和它需要的 schema 变更。
- 在同一测试库重跑库存、销售和两会话脚本。验收记录应能查到对应的会话号、订单或采购单、商品、前后库存和流水。按实际输出补齐阶段报告和组内分工记录。
