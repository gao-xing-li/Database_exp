# 第7—9周：Web应用与集成测试验收

本阶段交付可运行的Flask与SQL Server应用、角色界面、现货业务事务，以及集成测试和浏览器证据。第7周检查分层与核心操作，第8周检查订单、库存、价格和事务，第9周检查集成、权限与异常。三周共用本目录的一套完整应用，可按下面三个清单分别验收。

本阶段可以直接从空环境初始化，不要求助教已运行第5周或第6周验收。所需文件为本目录、同级[第1—4周建库代码](../第1-4周_建库代码/README.md)，以及同级第6周的[migration.sql](../第6周_函数依赖规范化与迁移/migration.sql)。初始化读取这些正式文件，独立创建自己的应用库，不复用第5、6周的验收数据库。

## 交付与验收对照

| 本阶段内容 | 文件入口 | 检查重点 |
| --- | --- | --- |
| 技术方案与范围 | [第7-9周 设计与决策.md](第7-9周%20设计与决策.md) | 角色、现货范围、价格与事务取舍 |
| 分层、身份、事务与接口 | [01_架构与接口.md](01_架构与接口.md) | 页面/路由、Services、Database/Repository、SQL约束与RLS的职责 |
| 角色操作与密码重设 | [02_操作手册.md](02_操作手册.md) | 五个样例账号、四类角色、具体页面操作与恢复步骤 |
| 可运行源代码 | [run.py](代码/web/run.py)、[路由与应用入口](代码/web/app/__init__.py)、[services.py](代码/web/app/services.py)、[repository.py](代码/web/app/repository.py)、[db.py](代码/web/app/db.py) | 业务规则与数据访问分层，参数化SQL、统一事务和异常 |
| 页面 | [index.html](代码/web/app/templates/index.html)、[app.js](代码/web/app/static/app.js)、[style.css](代码/web/app/static/style.css) | 按角色区分菜单、字段和操作，搜索、刷新、弹窗与移动布局 |
| 环境与初始化 | [requirements.txt](代码/web/requirements.txt)、[init_demo.py](代码/web/scripts/init_demo.py)、[01_web_security.sql](代码/web/sql/01_web_security.sql)、[配置样例](代码/web/config.example.json) | 独立建库、哈希认证、受限SQL账户、序列和顾客行级过滤 |
| 自动测试实现 | [test_integration.py](代码/web/tests/test_integration.py)、[conftest.py](代码/web/tests/conftest.py)、[test_password_reset.py](代码/web/tests/test_password_reset.py) | 42项真实SQL集成与6项密码辅助测试 |
| 浏览器与证据导出 | [browser_smoke.py](代码/web/scripts/browser_smoke.py)、[export_evidence.py](代码/web/scripts/export_evidence.py) | 实际角色流程、页面错误、截图和结果导出 |
| 原始结果与限度 | [03_测试与验证记录.md](03_测试与验证记录.md)、[pytest.xml](测试结果/pytest.xml)、[浏览器7组结果](测试结果/browser_price_lock.json) | 结果、覆盖范围、历史记录与未实现内容 |
| 截图与协作 | [角色流程截图](截图_角色流程/成功结账.png)、[登记锁价复核截图](截图_登记锁价复核/price_lock_before_checkout.png)、[分工](04_第二阶段分工.md)、[补图清单](05_本轮实机截图清单.md) | 图中账号、业务记录及其解释，成员待补拍事项 |
| 本阶段AI辅助过程 | [ai_log.md](ai_log.md) | 技术与业务讨论、实施修订和各轮验证过程，最新结果按README及验证记录查阅 |

## 从空环境安装与初始化

使用Python 3.12、SQL Server和PowerShell。下例以Windows本机SQL Server、TCP端口1433为例，端口不同时修改DB_PORT。SSMS用于准备实例和只读核对，SQL Server服务负责数据保存。

先在SSMS确认Windows登录有建库和创建SQL登录的权限；SQL Server启用“SQL Server和Windows身份验证模式”，对应实例启用TCP/IP并设置端口，修改后重启对应SQL Server服务。Windows集成身份初始化另需本机安装ODBC Driver 18 for SQL Server；网页运行通过pymssql和自动生成的受限SQL账户连接。

在**本阶段目录**打开PowerShell：

```powershell
conda create --prefix ./.conda-env python=3.12 pip -y
conda activate ./.conda-env
Set-Location './代码/web'
python -m pip install -r requirements.txt -r requirements-windows.txt
$env:DB_ADMIN_TRUSTED = '1'
$env:DB_SERVER = '127.0.0.1'
$env:DB_PORT = '1433'
$courseDemoSecure = Read-Host '设置12至200位的演示网页密码' -AsSecureString
$env:COURSE_DEMO_PASSWORD = [System.Net.NetworkCredential]::new('', $courseDemoSecure).Password
python scripts/init_demo.py
python run.py
```

初始化依次执行根目录基础01—07、第6周正式migration.sql和本阶段Web安全SQL，建立 `AnimeGoodsStoreDB_Week6App`、编号序列、认证数据和受限账户，并生成本机 `代码/web/config.local.json`。开始连接数据库前会检查基础文件和迁移文件是否齐全；配置或专用库已存在时停止，不自动清空。不要手动在应用库重复执行原01，也不要先运行迁移再调用初始化。

浏览器打开 [http://127.0.0.1:5000](http://127.0.0.1:5000)，输入下表账号及刚设置的密码。五个演示账号共用该次自行设置的网页密码，SQL账户密码由初始化随机生成。配置、口令、环境、日志与本地验收输出不提交GitHub。

如果使用SQL管理账号而非Windows身份，安装基础requirements即可；不设置DB_ADMIN_TRUSTED，设置DB_ADMIN_USER、DB_ADMIN_PASSWORD、DB_SERVER和DB_PORT后使用同一初始化脚本。管理口令只用于初始化，通过安全输入提供，不写入网页配置。

### 已有环境再次启动

在本阶段目录激活原环境，进入代码目录即可，不重新初始化：

```powershell
conda activate ./.conda-env
Set-Location './代码/web'
python run.py
```

使用Ctrl+C停止。忘记网页密码时按[操作手册](02_操作手册.md)生成并在SSMS执行密码重设SQL；保留现有商品、库存和订单。遇到缺依赖，核对同级阶段目录；连接失败则核对SQL服务、TCP端口与配置指向的实例。

## 第7周验收：分层、登录与商品操作

| 检查项 | 操作 | 通过标准 |
| --- | --- | --- |
| 应用分层 | 对照架构图查看路由、services.py、repository.py、db.py及页面 | 路由接收请求，业务层检查规则和权限，数据层用参数化SQL并管理连接/事务 |
| 登录与角色 | 依次登录manager、clerk、inventory、customer1/customer2 | 页面和权限符合下表；直接请求受保护接口也会验证身份与角色 |
| 商品查询与维护 | manager查询、新增、修改商品资料/售价/状态，再删除无引用的零库存商品 | 新增自动带零库存，保存后重新查询一致；有历史引用的商品不能硬删除，可停售 |
| 商品/库存分工 | 比较店长两个页面和库存员页面 | 商品页维护资料，库存页展示实际、预留、可售和警戒值，操作按角色开放 |

| 账号 | 角色及主要可验收操作 |
| --- | --- |
| manager | 店长：商品维护、库存调整、现货订单查询与销售操作 |
| clerk | 店员：商品目录、会员选择、草稿及明细、结账与取消；不能维护商品资料 |
| inventory | 库存员：仅库存管理入口，查询库存与调整实际数量和警戒值，不读会员和销售订单 |
| customer1 | 顾客，绑定会员1：在售商品及本人订单/明细，只读 |
| customer2 | 顾客，绑定会员2：用于与customer1交叉检查订单隔离 |

## 第8周验收：库存、订单、锁价与事务

按[操作手册](02_操作手册.md)逐项操作。使用专用演示商品与订单，记录本次实际编号、金额和前后库存。

| 检查项 | 操作 | 通过标准 |
| --- | --- | --- |
| 库存调整 | manager或inventory调整实际量、警戒值 | 可售=实际−预留；实际量不能低于预留量，不能直接清除预留 |
| 草稿生命周期 | clerk选会员建草稿，添加两种商品，改数量、移除明细、刷新，分别演示删除和取消草稿 | 草稿不扣库存；删除需确认，取消保留记录；完成和取消后不能再按草稿修改 |
| 登记锁价 | 以25元首次登记商品，manager将目录改成30元，clerk刷新、改成2件并结账 | 原单价仍25元，2件合计50元；新登记采用30元；移除后重加重新核对当前标价 |
| 过期标价拒绝 | 保持店员旧目录，店长调价后从旧页面尝试首次登记 | 提示刷新核对，不能把已过期的显示标价悄悄替换或写入 |
| 成功多商品结账 | 库存足够的两件商品在一张草稿中结账 | 沿用登记单价，统一扣库存并完成订单，之后只读；预留数量保持 |
| 整单回滚 | 后处理商品数量超过可售量，再结账；前后比较两件商品库存与订单 | 提示库存不足，先处理商品的扣减一起撤销，草稿及原登记单价保留 |
| 并发与锁 | 结合test_integration.py并发用例及db.py/repository.py说明锁顺序 | 两单争抢同一份可售量只允许一单成功，另一单失败，库存不被超卖 |

结账以同一事务完成校验、明细读取、库存扣减和订单完成，采用订单锁、统一商品顺序及带库存条件的更新；编号由Sequence生成，回滚后允许有编号空缺。

人工截图组曾使用两商品库存10/5，成功260元后变成8/4；失败草稿320元，失败后仍8/4。自动锁价复核组使用25元登记、30元目录、2件50元。这是两组不同演示，金额无需一致，验收应追踪同一组实际商品与订单。

## 第9周验收：集成、权限与错误处理

| 检查项 | 方式 | 通过标准 |
| --- | --- | --- |
| 输入与认证 | 空值、非法数量/金额、未登录、无CSRF或会话失效请求 | 按错误类型拒绝，数据不被部分写入 |
| 角色与SQL权限 | 直接API越权、受限SQL账户越权及两位顾客交叉查询 | 服务层拒绝越权；数据库账户保护表/列，顾客订单和明细受RLS及会员过滤 |
| 事务与状态 | 运行多商品、库存不足、并发、重复结账等用例 | 原子提交或整单回滚，完成单不可重复扣减 |
| 连接异常与日志 | 结合现有集成用例检查不可用端口场景 | 返回503及请求编号，服务端可定位日志，页面不显示驱动连接细节 |
| 浏览器与刷新 | 切换角色、查询、弹窗、页面刷新、390像素布局 | 菜单/字段符合角色，刷新重新查询且不改登记单价，无页面脚本错误和整体横向溢出 |

在 `代码/web/` 使用**本次初始化设置的同一密码**运行测试。若是新PowerShell窗口，先重新通过Read-Host安全设置COURSE_DEMO_PASSWORD。测试使用专用Week6App库，暂停同时进行的人工操作。

```powershell
New-Item -ItemType Directory -Path './results' -Force | Out-Null
python -m pytest -q --junitxml=results/pytest.local.xml
```

预期收集并通过48项：42项连接真实SQL Server，6项密码辅助。缺少本地配置或口令时不能完成集成测试，仅收集成功不等于执行通过。测试创建并清理自身数据，序列编号消耗保留。新结果写入代码目录results，不覆盖提交中的既有证据。

可只运行无需数据库的密码辅助测试：

```powershell
python -m pytest tests/test_password_reset.py -q
```

可选真实浏览器复验：先保持 `python run.py` 运行，在另一个激活同环境、设置同一密码的PowerShell窗口进入代码/web，再执行：

```powershell
python -m pip install -r requirements-browser.txt
python -m playwright install chromium
$env:COURSE_BROWSER_OUTPUT = 'results/screenshots.local'
python scripts/browser_smoke.py
```

默认访问127.0.0.1:5000，创建并清理本次测试商品和订单；截图写入COURSE_BROWSER_OUTPUT目录，结果默认写入代码目录的 `results/browser.json`，也可用COURSE_BROWSER_RESULT指定其他本地文件。记录API响应或业务证据的方法见[验证记录](03_测试与验证记录.md)和[导出脚本](代码/web/scripts/export_evidence.py)。

## 已有证据与本次复验分开记录

| 保留材料 | 已有结果与用途 |
| --- | --- |
| [pytest.xml](测试结果/pytest.xml) | 最新完整48项通过，0失败/错误/跳过，42项SQL集成+6项密码辅助 |
| [browser_price_lock.json](测试结果/browser_price_lock.json) | 完整浏览器7组通过，含角色、锁价、结账和顾客隔离；对应[9张复核截图](截图_登记锁价复核/01_login.png)所在目录 |
| [role_views.json](测试结果/role_views.json) | 五账号21项只读页面检查，非21组业务写入流程 |
| [order_refresh.json](测试结果/order_refresh.json) | 3项只读刷新检查，无业务写入 |
| [password_reset_tests.xml](测试结果/password_reset_tests.xml) | 6项密码辅助独立记录，已包含在48项中，不能再次相加 |
| [api_examples.json](测试结果/api_examples.json) | 前期API正常/错误响应示例；字段语义可参考，样例值属于当时环境 |
| [角色流程截图](截图_角色流程/登录页面.png)所在目录 | 本机人工操作组，含成功结账、失败回滚、商品维护及顾客隔离 |

[验证记录](03_测试与验证记录.md)解释执行背景与限度。本次提交目录整理没有重新运行SQL集成或完整浏览器业务测试，也不把既有结果写成组员本次本人复跑。本人补拍范围继续按[实机截图清单](05_本轮实机截图清单.md)完成。

当前现货流程、四角色、登记锁价、整单事务已实现。预售履约、采购验收、到货数量与状态联动、会员资料与账号管理、库存流水和支付尚未实现；更大规模压力测试、公网部署和生产故障恢复未验证。这些边界同时适用于第7、8、9周的讲解，不能仅凭数据库有相关表就认定界面和业务流程已完成。

[返回提交总说明](../README.md)
