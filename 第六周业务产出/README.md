# 第六周业务产出

本周完成 15 张表的依赖、更新异常与范式分析，保留全部 96 个字段，并在 SQL Server 隔离副本上实施三项采购限制：非空活动关联唯一、采购类型与活动关联一致、移除部分到货状态。

**实测：迁移成功，45 项回归全部 PASS，三类迁移冲突均被预期拒绝，已迁移副本再次执行被阻止。** 环境与结果解释见 [验证记录](03_迁移与回归验证记录.md)。第六周数据库成果已形成，完整 Web 应用仍属第 7—9 周任务。

## 阅读顺序

1. [设计与决策](../第六周%20设计与决策.md)：范围与小组取舍。
2. [依赖与范式分析](01_依赖与范式分析.md)：逐表候选码、依赖、三类异常与范式依据，含独立分解示例。
3. [重构方案与数据字典](02_重构方案与数据字典.md)：15 张表的全部字段、码、外键、CHECK 和冗余维护说明。
4. [ER 总图](ER图/01_总图.svg)与[可编辑源图](ER图/ER模型.drawio)：四页教材记法，另有三个局部图及 PNG。
5. [migration.sql](migration.sql)、[regression.sql](regression.sql)与[验证记录](03_迁移与回归验证记录.md)：代码、顺序、预期与实测。
6. [报告素材](04_报告素材.md)、[AI 记录](ai_log.md)：供第二阶段报告引用与人工补充。

## 当前可检查的实验库

本次使用本机 SQL Server 实例 `DESKTOP-NLE7LS7`，Windows 身份连接，保留两个用途明确的实验库：

| 库 | 状态与用途 |
| --- | --- |
| `AnimeGoodsStoreDB_Week6Baseline` | 原始 00—07 生成的完整 v0.1 样例基线，供只读对照 |
| `AnimeGoodsStoreDB_Week6Target` | 从基线取得的数据及完整 v0.1 结构，再实施第六周迁移；可直接查看或运行回归 |

这些库是课程样例实验库，不是原 `AnimeGoodsStoreDB` 的在营数据备份。原库本次检查为 15 表、0 视图、商品与订单均为空，因此采用原始脚本准备独立样例基线；原库没有重建或补齐。冲突测试使用的第三个专用库在验证后清理。

已迁移的 Target **直接运行回归即可**；再次运行迁移会返回 51005，这是一次迁移的前提检查，不是需要修补的失败。运行回归需对基线有读取权限，并能模拟第一阶段三个测试用户。

## 从空实验环境复现

环境要求：Microsoft SQL Server、SSMS；已验证实例支持过滤唯一索引、`THROW`、`DROP TABLE IF EXISTS` 和 `CREATE OR ALTER VIEW`。新 SQL 文件为 UTF-8；第一阶段 00—05 原文件是 GB18030，06—07 为 UTF-8，打开时注意正确显示中文。

1. **建立独立基线**。在 SSMS 新建数据库 `AnimeGoodsStoreDB_Week6Baseline`。从工作区 `Database_exp/第1-4周业务产出/` 按顺序打开 00—07，把查询编辑器中执行文本的 `AnimeGoodsStoreDB` 替换为该基线库名，再执行；不覆盖原始文件。第一阶段 01 会删表，必须核对其 `USE` 指向新的实验基线。
2. **取得目标副本**。可通过 SSMS 备份/还原把基线恢复为 `AnimeGoodsStoreDB_Week6Target`，并使用不同物理文件路径。本次实测采用等价的课程复现方式：新建 Target，在其中运行原 01 的改库名执行文本，按下面顺序复制 15 表数据，再运行原 05、06、07 的改库名文本。这样约束、视图、角色、测试用户和数据均齐全，原始时间值也保留。
3. **保存迁移前结果**。连接基线或未迁移目标，导出 `vw_OrderDetail`、逐订单金额、`vw_ProductSalesSummary`、`vw_InventoryStatus` 的结果。本目录 `results/before_*.csv` 为本次基线值；本次实测还在回归中逐表比较全部列。
4. **迁移**。在 SSMS 数据库下拉框选中 `AnimeGoodsStoreDB_Week6Target`，打开 `migration.sql` 执行。文件不含 `USE`，不会自动切回原库；当前数据库名要求含 `Week6`。遇到列出的重复活动、错误类型关联或旧状态冲突时停止，不自动改数据。
5. **回归**。保持连接 Target，打开新的查询窗口，执行 `regression.sql`。顶部 `@BaselineDatabase` 默认指向上述基线；改名时同步修改。基线和目标必须在同一实例且是不同数据库。结果应为 45 PASS、0 FAIL；任一 FAIL 最终抛出 51199。样例父表不能为空，测试编号 986000—986099 不得与业务数据冲突。
6. **保存与解释结果**。导出判定表、汇总和业务值，并参考验证记录说明差异。目标结构不拆表、不改数据，预期各表行数和内容均相同；新增限制改变的是后续允许写入的数据范围。

若按本次的 DDL 与数据复制方式取得 Target，在执行复制前必须确认 Target 已有 15 张空表，且当前连接为 Target：

```sql
-- 在新的 AnimeGoodsStoreDB_Week6Target 中执行；基线仅作数据来源。
INSERT dbo.ProductCategory SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.ProductCategory;
INSERT dbo.AnimeIP SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.AnimeIP;
INSERT dbo.BusinessRole SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.BusinessRole;
INSERT dbo.Member SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.Member;
INSERT dbo.Supplier SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.Supplier;
INSERT dbo.CharacterInfo SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.CharacterInfo;
INSERT dbo.Employee SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.Employee;
INSERT dbo.Product SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.Product;
INSERT dbo.Inventory SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.Inventory;
INSERT dbo.PresaleActivity SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.PresaleActivity;
INSERT dbo.PresaleReservation SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.PresaleReservation;
INSERT dbo.PurchaseOrder SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.PurchaseOrder;
INSERT dbo.PurchaseOrderItem SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.PurchaseOrderItem;
INSERT dbo.SalesOrder SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.SalesOrder;
INSERT dbo.SalesOrderItem SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.SalesOrderItem;
```

## 冲突与恢复

迁移前提或冲突不满足时，错误号为 51000—51007，停止后根据消息检查环境或具体记录。修改全部置于事务内，未提交失败由 CATCH 回滚；成功后若要从头演示，重新取得未迁移 v0.1 副本，不能在已迁移库上运行原 01 来冒充数据迁移。没有自动删改冲突数据或通用降级脚本。

本次 `results/migration_conflicts.csv` 记录重复活动、错误补货关联、旧状态三类冲突及重复执行前提检查。冲突测试没有交付额外运行器；复验时可在另一个可丢弃的 v0.1 副本中分别构造这些情况，执行迁移并核对 51007、原记录保留且未出现新索引，勿污染留作对照的 Baseline。

## 文件与阶段边界

本周只需要回答三个问题：现有结构为什么保留或调整；三项采购限制能否在保留数据的前提下落地；迁移后查询与权限是否保持。按任务原文复核后的交付取舍如下：

| 内容 | 对应要求与取舍 |
| --- | --- |
| 15 表依赖分析、目标模式与数据字典 | 明确要求逐表说明；字段释义和范式依据必须准确，不只统计数量 |
| ER 图 | 作业明确要求更新；复用第五周实体、属性、联系和布局，仅更新落实说明。四页及 SVG/PNG 是沿用的展示形式，不是额外建模成果，也不是课程要求的固定文件数量 |
| 独立分解示例 | 任务允许现有结构合理时采用；只放在分析文档，不新增演示表或程序 |
| 两个 SQL 与结果 | 对应保留数据的迁移、查询/完整性/权限回归；45 项中多数是逐表和分组对照，不代表新增 45 项业务功能 |
| README、报告素材、ai_log | 作业明确要求；分别承担复现、报告引用和过程记录，运行事实统一以验证记录及 CSV 为准 |
| 库存联动、验收事务、应用界面 | 属于第 7—9 周，继续不在本周实现；不另加收货数量零/全量或整单一致性控制 |

`results/` 保留 CSV 原始对照、回归错误消息和基线准备摘要。四页 ER 图中的 U1 表示已验证的活动唯一及类型关联限制；Δ2 说明只移除了部分到货状态，`received_qty` 及其原范围约束仍保留。没有新增单条零/全量、整单一致性约束或相关专项测试。库存联动、完整验收和销售事务继续留应用阶段。

文件尚放在 `week5-9/第六周业务产出/`，未自动搬入组内 `Database_exp`。第一阶段与第五周原始文件保持其阶段状态；后续并入 v1.0 时，应连同本周分析、图、脚本和验证记录一起组织。
