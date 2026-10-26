# 第1—4周建库代码：各阶段共用的v0.1起点

本目录在“第二阶段提交”根目录单独保存基础00—07，供第5周ER展示、第6周迁移和第7—9周Web初始化使用。它不是Web专属依赖，也不代替各周新增成果。原始SQL与仓库第一阶段文件保持相同字节。

## 基础文件与顺序

| 文件 | 用途 | 原编码 |
| --- | --- | --- |
| [00_create_database.sql](00_create_database.sql) | 创建或复用原名数据库；原始入口留档 | GB18030 |
| [01_create_tables.sql](01_create_tables.sql) | 重建15张业务表、主外键与原约束，会清空这些表的数据 | GB18030 |
| [02_insert_sample_data.sql](02_insert_sample_data.sql) | 装入固定商品、库存、会员、员工、销售与采购样例 | GB18030 |
| [03_crud.sql](03_crud.sql) | 基础增删改查演示，演示新增记录最终删除 | GB18030 |
| [04_query.sql](04_query.sql) | 九组业务查询 | GB18030 |
| [05_view.sql](05_view.sql) | 四个视图及查询展示 | GB18030 |
| [06_constraint.sql](06_constraint.sql) | 补充约束与16项正反例 | UTF-8 |
| [07_role.sql](07_role.sql) | 三类数据库角色、测试用户与6项权限正反例 | UTF-8 |

打开原SQL时按编码读取，中文注释与字符串都应正确显示。原文件包含 `USE AnimeGoodsStoreDB`，直接执行会切换数据库；仅改变SSMS下拉框不足以改变执行目标。

## 为第5、6周生成执行副本

在“第二阶段提交”目录打开PowerShell，使用Python 3.12运行下列命令之一。不需要安装第三方包，也无需启动Flask。

```powershell
# 仅验收第5周
python './第1-4周_建库代码/prepare_acceptance.py' week5

# 仅验收第6周，与第5周相互独立
python './第1-4周_建库代码/prepare_acceptance.py' week6
```

[prepare_acceptance.py](prepare_acceptance.py)只生成本地SQL文件，不连接或修改数据库。输出位于提交根目录 `验收准备.local/week5/` 或 `验收准备.local/week6/`，统一为带BOM的UTF-8，原始SQL保持原样。已存在的输出目录会拒绝覆盖，可保留已有执行副本直接使用。此目录由Git忽略。

在SSMS连接自己的SQL Server实例，按所选阶段 README 逐个执行生成文件。生成的00文件只允许新建专用库，库已存在就报51200并停止；遇到任何非预期错误，都应停止，核对后再继续，不能跳过错误执行下一个文件。重复验收已有库时直接执行对应查询或回归，不重新执行建库与01脚本。

- 第5周生成00—08：新建 `AnimeGoodsStoreDB_Week5Review`，基础01—07，最后执行三个只读查询。只依赖基础SQL与第5周查询文件。
- 第6周生成00—07、10—15、20—21：独立建立Baseline，再取得数据完全相同的Target，最后迁移和回归。只依赖基础SQL与第6周两个正式脚本，不读取第5周文件。
- 第7—9周使用本阶段 `代码/web/scripts/init_demo.py`，直接读取本目录01—07和第6周正式迁移，不需要生成上述执行副本，也不使用前两周的验收数据库。

## 不使用生成工具时

第5周可用SSMS新建 `AnimeGoodsStoreDB_Week5Review`，将01—07的执行文本中 `AnimeGoodsStoreDB` 替换为该专用库名，按顺序执行；最后同样替换第5周只读查询的USE目标。只编辑执行副本，原文件不覆盖。

第6周先按同样方法新建并装载 `AnimeGoodsStoreDB_Week6Baseline`。目标库必须取得相同原始时间值和全部数据，不能再独立运行02样例脚本；新建Target、建表后按外键顺序从Baseline复制15表全部列，再执行05—07。完整文件顺序、复制顺序和回归判定见[第6周说明](../第6周_函数依赖规范化与迁移/README.md)。

## 从这里返回

[总说明](../README.md) · [第5周验收](../第5周_ER模型与业务规则/README.md) · [第6周验收](../第6周_函数依赖规范化与迁移/README.md) · [第7—9周验收](../第7-9周_Web应用与集成测试/README.md)
