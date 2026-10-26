# 第6周：函数依赖、规范化与迁移验收

本周从v0.1结构出发，完成15张表的依赖、更新异常与范式分析，保留96个字段，说明保留与调整的依据，并在保留数据的目标副本上落实三项采购限制。验收包括理论论证、目标模式、实际迁移和前后回归四部分。

单独验收只需要本目录与提交根目录的[第1—4周建库代码](../第1-4周_建库代码/README.md)。本周自行建立Baseline和Target，不依赖助教已执行第5周查询，不需要Web环境，也不使用第7—9周人工演示数据。

## 交付与验收对照

| 本周内容 | 交付文件 | 验收时检查什么 |
| --- | --- | --- |
| 设计与取舍 | [第六周 设计与决策.md](第六周%20设计与决策.md) | 本周承接的问题、调整范围、保留结构的理由 |
| 依赖与规范化 | [01_依赖与范式分析.md](01_依赖与范式分析.md) | 逐表候选码、函数依赖、三类异常、范式依据；独立分解示例的无损连接和依赖保持 |
| 目标模式与字段 | [02_重构方案与数据字典.md](02_重构方案与数据字典.md) | 15表、96字段的含义、码、外键、CHECK、历史语义与冗余维护 |
| 更新ER图 | [可编辑源图](ER图/ER模型.drawio)；[总图](ER图/01_总图.svg)、[商品与库存](ER图/02_商品与库存.svg)、[销售与人员](ER图/03_销售与人员.svg)、[预售与采购](ER图/04_预售与采购.svg)，同目录各有PNG | 沿用四页实体关系模型，更新采购限制落实标记与图例 |
| 数据保留迁移 | [migration.sql](migration.sql) | 前提检查、冲突报告、事务、过滤唯一索引与两个CHECK的调整 |
| 回归实现 | [regression.sql](regression.sql) | 前后数据/查询/元数据/权限比较，合法与非法写入、最终失败判定 |
| 实测与原始结果 | [03_迁移与回归验证记录.md](03_迁移与回归验证记录.md)、[results/summary.csv](results/summary.csv)、[results/regression.csv](results/regression.csv) | 45 PASS、0 FAIL的已有证据，迁移冲突和前后CSV |
| 报告与过程 | [04_报告素材.md](04_报告素材.md)、[ai_log.md](ai_log.md) | 理论与实测的引用范围、讨论与人工复核要求 |

## 理论分析与实际修改分别看什么

理论部分解释每张表的候选码、非平凡依赖、插入/删除/更新异常及范式，说明为什么业务模式继续保留15张表。IP与角色涉及群像商品和归属一致性，成交单价、需求快照及计划量保留历史含义；订单总额、可售库存采用查询计算。独立教学关系用于证明分解性质，不作为实际业务迁移新增的表。

实际迁移只落实以下三项，既不拆表也不改写原数据：

| 采购规则 | 落地方式 | 应验证的边界 |
| --- | --- | --- |
| 同一预售活动最多一张采购单 | 非空presale_id的过滤唯一索引 | 取消单也占用唯一关联；多张无活动普通补货允许共存 |
| 类型与活动双向一致 | 替换采购类型CHECK | PRESALE必须关联活动；RESTOCK不得关联活动 |
| 采购不再使用部分到货状态 | 收紧采购状态CHECK | PARTIAL_RECEIVED拒绝；ORDERED和合法RECEIVED允许 |

`received_qty`及原范围约束仍保留，未增加零/全量或整单一致性控制。采购完成不自动增加库存，预售履约、采购验收事务仍属后续范围。本周回归通过不代表这些业务联动已实现。

## 从空环境准备两个独立数据库

使用SQL Server、SSMS，执行者需有建库、创建对象、读取两库、授权及EXECUTE AS测试用户的权限。Baseline与Target必须位于同一实例、名称不同。准备工具仅使用Python标准库。

在本目录打开PowerShell：

```powershell
python '../第1-4周_建库代码/prepare_acceptance.py' week6
```

生成的执行副本位于 `../验收准备.local/week6/`，统一为UTF-8。工具只生成文件，不连接数据库，不读取第5周成果。然后在SSMS连接自己的实例，严格按下表逐个执行；遇到非预期错误立即停止，不执行后续文件。

| 顺序 | 生成文件 | 执行目标与预期 |
| --- | --- | --- |
| 00 | `00_新建基线库.sql` | 新建AnimeGoodsStoreDB_Week6Baseline；已存在则51200并停止 |
| 01—07 | 基础01—07执行副本 | 在Baseline建立完整v0.1，含样例、视图、约束、角色及测试用户；基础16+6项PASS |
| 10 | `10_新建目标库.sql` | 新建AnimeGoodsStoreDB_Week6Target；已存在则停止 |
| 11 | `11_目标建表.sql` | 在Target建立15张空表和原约束 |
| 12 | `12_复制全部基线数据.sql` | 按外键顺序将Baseline的15表全部列复制到Target，保留原始时间值；一个事务内完成 |
| 13—15 | `13_view.sql`、`14_constraint.sql`、`15_role.sql` | 在Target补齐原视图、约束、角色与测试用户，此时仍为v0.1 |
| 20 | `20_执行第六周迁移.sql` | 在Target执行本目录migration.sql的副本，成功提交三项限制 |
| 21 | `21_执行第六周回归.sql` | 在Target执行regression.sql的副本；默认读取上述Baseline，预期45 PASS、0 FAIL |

生成文件都指向表中专用库。原01会重建表，只能在本次新库的准备阶段执行；已迁移Target直接运行21回归即可。不得在两库分别重新运行02来构造所谓相同基线，因为默认时间等字段可能不同，回归会逐列比较。

不使用工具时，可按同一顺序在SSMS准备：新建Baseline，替换原01—07执行文本的USE目标并装载；新建Target，仅运行改库名的01，再按ProductCategory、AnimeIP、BusinessRole、Member、Supplier、CharacterInfo、Employee、Product、Inventory、PresaleActivity、PresaleReservation、PurchaseOrder、PurchaseOrderItem、SalesOrder、SalesOrderItem顺序执行 `INSERT dbo.表名 SELECT * FROM AnimeGoodsStoreDB_Week6Baseline.dbo.表名`，然后运行改库名的05—07。也可备份/还原Baseline取得数据相同且物理文件分开的Target。原始脚本不覆盖。

## 现场迁移与回归

1. 在迁移前检查Baseline和Target都有完整15表、4视图、相同数据、原角色及测试用户。可在Target先查询原采购约束，解释v0.1允许范围。
2. 执行20，或在SSMS明确选择Target后执行正式[migration.sql](migration.sql)。正式文件不含USE，当前库名必须含Week6，且不能已有事务。成功后检查新增索引和两个受信任CHECK。
3. 在新的Target查询窗口执行21，或执行正式[regression.sql](regression.sql)。默认 `@BaselineDatabase=N'AnimeGoodsStoreDB_Week6Baseline'`；库改名时须同步修改执行副本。执行者必须能读取Baseline并模拟测试用户。
4. 判定表预期为45 PASS、0 FAIL。任一FAIL最终抛51199；不能只凭迁移“执行成功”判断完成。测试写入在事务中回滚，编号986000—986099须未被业务占用。
5. 对照前后查询及元数据，解释本周改变的是允许写入的数据范围，原业务数据、字段、视图和权限应保持。保存本次实际结果，不以已有CSV冒充重新执行的结果。

| 回归部分 | 项数 | 通过标准 |
| --- | --- | --- |
| 全表数据 | 15 | 每张表全部列双向EXCEPT为空且行数相同 |
| 查询 | 5 | 订单详情、逐订单金额、销量、库存、会员统计相同 |
| 元数据 | 7 | 保留列/默认值、CHECK、外键、索引、视图、角色授权及成员关系 |
| 目标限制 | 1 | 新索引及两个CHECK存在、启用且受信任 |
| 合法写入 | 4 | 多张普通补货、新活动采购、ORDERED、合法RECEIVED成功后回滚 |
| 非法写入 | 7 | 重复活动、类型关联错误、旧状态及原外键/数量/业务编号反例被预期对象拒绝 |
| 权限 | 6 | 店员销售、库存员警戒值、店长售价允许，相应越权操作拒绝 |

## 原始结果与常见异常

已有2026-10-22隔离实测为45 PASS、0 FAIL，详见[回归CSV](results/regression.csv)、[汇总](results/summary.csv)和[验证记录](03_迁移与回归验证记录.md)。迁移前后订单明细8行、6笔订单合计530元，6件商品可售量合计42；`before_*.csv`与对应迁移后CSV保留业务值，执行环境见[environment.csv](results/environment.csv)，基础执行摘要见[baseline_setup.txt](results/baseline_setup.txt)。本次整理未重跑这些SQL测试。

迁移前发现重复活动、错误类型关联或旧状态时，返回51007并保留原记录，不自动修数据；已迁移Target再次运行迁移返回51005，应直接回归。其他51000—51007按消息核对前提，未提交修改由事务回滚。

三类冲突及重复执行的已有证据见[migration_conflicts.csv](results/migration_conflicts.csv)。如需现场构造冲突，应另用可丢弃的v0.1副本，勿污染Baseline或已验收Target。成功迁移后要重演，需重新取得未迁移副本；没有通用降级脚本。理论论证、数据保持和列出的写入检查各有边界，不能互相代替。

[返回提交总说明](../README.md)
