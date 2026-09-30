/* =========================================================
   07_role.sql
   二次元周边商品店：数据库角色与权限验证

   执行前：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql
   04_query.sql
   05_view.sql
   06_constraint.sql

   本文件：
   1. 创建三个数据库角色
   2. 按最小权限原则授权
   3. 创建 WITHOUT LOGIN 测试用户
   4. 验证正常操作成功
   5. 验证越权操作失败
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   第一部分：创建数据库角色
   ========================================================= */

IF DATABASE_PRINCIPAL_ID(N'dbrole_sales_clerk') IS NULL
    EXEC(N'CREATE ROLE dbrole_sales_clerk AUTHORIZATION dbo;');
GO

IF DATABASE_PRINCIPAL_ID(N'dbrole_inventory_manager') IS NULL
    EXEC(N'CREATE ROLE dbrole_inventory_manager AUTHORIZATION dbo;');
GO

IF DATABASE_PRINCIPAL_ID(N'dbrole_store_manager') IS NULL
    EXEC(N'CREATE ROLE dbrole_store_manager AUTHORIZATION dbo;');
GO



/* =========================================================
   第二部分：销售 / 收银店员权限
   ========================================================= */

/*
   可以：
   - 查看商品、库存状态
   - 查看和维护会员
   - 查看预售、预订
   - 创建和处理销售订单
   - 确认预售提货状态

   不可以：
   - 修改库存
   - 管理供应商
   - 创建采购订单
   - 管理员工
*/


/* 商品查询 */
GRANT SELECT
ON OBJECT::dbo.Product
TO dbrole_sales_clerk;
GO


/* 使用库存状态视图，不直接修改 Inventory */
GRANT SELECT
ON OBJECT::dbo.vw_InventoryStatus
TO dbrole_sales_clerk;
GO


/* 查看订单详情 */
GRANT SELECT
ON OBJECT::dbo.vw_OrderDetail
TO dbrole_sales_clerk;
GO


/* 会员查询、登记和修改 */
GRANT SELECT, INSERT, UPDATE
ON OBJECT::dbo.Member
TO dbrole_sales_clerk;
GO


/* 查看预售活动 */
GRANT SELECT
ON OBJECT::dbo.PresaleActivity
TO dbrole_sales_clerk;
GO


/* 查看预订 */
GRANT SELECT
ON OBJECT::dbo.PresaleReservation
TO dbrole_sales_clerk;
GO


/*
   当前阶段允许店员修改预订状态，
   用于确认预售提货等业务。
*/
GRANT UPDATE (reservation_status)
ON OBJECT::dbo.PresaleReservation
TO dbrole_sales_clerk;
GO


/* 创建销售订单 */
GRANT INSERT
ON OBJECT::dbo.SalesOrder
TO dbrole_sales_clerk;
GO


/* 完成订单 */
GRANT UPDATE (order_status, order_time)
ON OBJECT::dbo.SalesOrder
TO dbrole_sales_clerk;
GO


/* 创建订单明细 */
GRANT INSERT
ON OBJECT::dbo.SalesOrderItem
TO dbrole_sales_clerk;
GO


/*
   在订单最终完成前，
   允许店员调整购买数量或成交单价。
*/
GRANT UPDATE (quantity, unit_price)
ON OBJECT::dbo.SalesOrderItem
TO dbrole_sales_clerk;
GO



/* =========================================================
   第三部分：库存管理员权限
   ========================================================= */

/*
   可以：
   - 查看商品和库存
   - 修改库存
   - 查看采购订单
   - 登记采购到货和验收

   不可以：
   - 查看会员信息
   - 创建销售订单
   - 决定采购订单
   - 管理员工
*/


GRANT SELECT
ON OBJECT::dbo.Product
TO dbrole_inventory_manager;
GO


GRANT SELECT
ON OBJECT::dbo.Inventory
TO dbrole_inventory_manager;
GO


GRANT SELECT
ON OBJECT::dbo.vw_InventoryStatus
TO dbrole_inventory_manager;
GO


/*
   库存管理员可以维护实际库存、
   预留库存、补货警戒值及更新时间。
*/
GRANT UPDATE
(
    on_hand_qty,
    reserved_qty,
    reorder_point,
    updated_at
)
ON OBJECT::dbo.Inventory
TO dbrole_inventory_manager;
GO


/* 查看采购订单与明细 */
GRANT SELECT
ON OBJECT::dbo.PurchaseOrder
TO dbrole_inventory_manager;
GO

GRANT SELECT
ON OBJECT::dbo.PurchaseOrderItem
TO dbrole_inventory_manager;
GO


/*
   到货验收后可以登记：
   - 验收时间
   - 验收员工
   - 采购状态
*/
GRANT UPDATE
(
    received_time,
    received_by,
    purchase_status
)
ON OBJECT::dbo.PurchaseOrder
TO dbrole_inventory_manager;
GO


/* 登记实际收到数量 */
GRANT UPDATE (received_qty)
ON OBJECT::dbo.PurchaseOrderItem
TO dbrole_inventory_manager;
GO



/* =========================================================
   第四部分：店长 / 管理员权限
   ========================================================= */

/*
   店长具有较完整的经营管理权限，
   但仍不直接授予 db_owner 或 db_datawriter。

   采用明确对象授权，
   保留最小权限原则。
*/


/* ---------- 经营统计 ---------- */

GRANT SELECT
ON OBJECT::dbo.vw_OrderDetail
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.vw_ProductSalesSummary
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.vw_InventoryStatus
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.vw_MemberConsumptionSummary
TO dbrole_store_manager;
GO


/* ---------- 商品基础资料 ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.ProductCategory
TO dbrole_store_manager;

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.AnimeIP
TO dbrole_store_manager;

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.CharacterInfo
TO dbrole_store_manager;

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.Product
TO dbrole_store_manager;
GO


/* ---------- 员工及业务角色 ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.BusinessRole
TO dbrole_store_manager;

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.Employee
TO dbrole_store_manager;
GO


/* ---------- 供应商 ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.Supplier
TO dbrole_store_manager;
GO


/* ---------- 预售活动 ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.PresaleActivity
TO dbrole_store_manager;
GO


/* 店长需要查看预订需求，但不直接修改会员预订 */
GRANT SELECT
ON OBJECT::dbo.PresaleReservation
TO dbrole_store_manager;
GO


/* ---------- 采购决策 ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.PurchaseOrder
TO dbrole_store_manager;

GRANT SELECT, INSERT, UPDATE, DELETE
ON OBJECT::dbo.PurchaseOrderItem
TO dbrole_store_manager;
GO


/* ---------- 其他经营数据只读 ---------- */

GRANT SELECT
ON OBJECT::dbo.Inventory
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.Member
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.SalesOrder
TO dbrole_store_manager;

GRANT SELECT
ON OBJECT::dbo.SalesOrderItem
TO dbrole_store_manager;
GO


/*
   店长可以制定库存警戒值，
   但当前不负责日常实际库存数量修改。
*/
GRANT UPDATE (reorder_point)
ON OBJECT::dbo.Inventory
TO dbrole_store_manager;
GO



/* =========================================================
   第五部分：创建测试用户
   WITHOUT LOGIN

   仅用于实验中验证数据库角色权限。
   不需要创建真实 SQL Server 登录账号。
   ========================================================= */

IF DATABASE_PRINCIPAL_ID(N'u_test_sales') IS NULL
    CREATE USER u_test_sales WITHOUT LOGIN;
GO

IF DATABASE_PRINCIPAL_ID(N'u_test_inventory') IS NULL
    CREATE USER u_test_inventory WITHOUT LOGIN;
GO

IF DATABASE_PRINCIPAL_ID(N'u_test_manager') IS NULL
    CREATE USER u_test_manager WITHOUT LOGIN;
GO



/* =========================================================
   第六部分：加入角色
   ========================================================= */

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r
        ON drm.role_principal_id = r.principal_id
    INNER JOIN sys.database_principals m
        ON drm.member_principal_id = m.principal_id
    WHERE r.name = N'dbrole_sales_clerk'
      AND m.name = N'u_test_sales'
)
BEGIN
    ALTER ROLE dbrole_sales_clerk
    ADD MEMBER u_test_sales;
END;
GO


IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r
        ON drm.role_principal_id = r.principal_id
    INNER JOIN sys.database_principals m
        ON drm.member_principal_id = m.principal_id
    WHERE r.name = N'dbrole_inventory_manager'
      AND m.name = N'u_test_inventory'
)
BEGIN
    ALTER ROLE dbrole_inventory_manager
    ADD MEMBER u_test_inventory;
END;
GO


IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r
        ON drm.role_principal_id = r.principal_id
    INNER JOIN sys.database_principals m
        ON drm.member_principal_id = m.principal_id
    WHERE r.name = N'dbrole_store_manager'
      AND m.name = N'u_test_manager'
)
BEGIN
    ALTER ROLE dbrole_store_manager
    ADD MEMBER u_test_manager;
END;
GO



/* =========================================================
   第七部分：正常权限测试
   ========================================================= */


/* ---------------------------------------------------------
   P1. 销售店员：
   正常创建并完成一笔销售订单
   --------------------------------------------------------- */

PRINT N'========== P1：销售店员正常销售操作 ==========';

BEGIN TRY
    BEGIN TRAN;

    EXECUTE AS USER = 'u_test_sales';

    INSERT INTO dbo.SalesOrder
    (
        order_id,
        order_no,
        order_type,
        member_id,
        cashier_id,
        reservation_id,
        order_time,
        order_status
    )
    VALUES
    (
        9301,
        'SO_ROLE_TEST',
        'SPOT',
        1,
        1,
        NULL,
        NULL,
        'CREATED'
    );

    INSERT INTO dbo.SalesOrderItem
    (
        order_id,
        product_id,
        quantity,
        unit_price
    )
    VALUES
    (
        9301,
        1,
        1,
        68.00
    );

    UPDATE dbo.SalesOrder
    SET
        order_status = 'COMPLETED',
        order_time = SYSDATETIME()
    WHERE order_id = 9301;

    PRINT N'[PASS] P1：销售店员可以正常创建和完成销售订单。';

    REVERT;

    ROLLBACK TRAN;
END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_sales'
        REVERT;

    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    PRINT N'[FAIL] P1：销售店员正常销售操作失败。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* ---------------------------------------------------------
   P2. 库存管理员：
   正常修改补货警戒值
   --------------------------------------------------------- */

PRINT N'========== P2：库存管理员正常库存操作 ==========';

BEGIN TRY
    BEGIN TRAN;

    EXECUTE AS USER = 'u_test_inventory';

    UPDATE dbo.Inventory
    SET
        reorder_point = 6,
        updated_at = SYSDATETIME()
    WHERE product_id = 1;

    PRINT N'[PASS] P2：库存管理员可以正常更新库存信息。';

    REVERT;

    ROLLBACK TRAN;
END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_inventory'
        REVERT;

    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    PRINT N'[FAIL] P2：库存管理员正常库存操作失败。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* ---------------------------------------------------------
   P3. 店长：
   正常修改商品当前售价

   仅作为权限测试，事务结束后回滚。
   --------------------------------------------------------- */

PRINT N'========== P3：店长正常商品管理 ==========';

BEGIN TRY
    BEGIN TRAN;

    EXECUTE AS USER = 'u_test_manager';

    UPDATE dbo.Product
    SET sale_price = 70.00
    WHERE product_id = 1;

    PRINT N'[PASS] P3：店长可以正常管理商品信息。';

    REVERT;

    ROLLBACK TRAN;
END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_manager'
        REVERT;

    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    PRINT N'[FAIL] P3：店长正常商品管理操作失败。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* =========================================================
   第八部分：越权操作测试
   ========================================================= */


/* ---------------------------------------------------------
   N1. 销售店员试图修改采购订单

   预期：
   权限不足，操作失败。
   --------------------------------------------------------- */

PRINT N'========== N1：销售店员越权修改采购订单 ==========';

BEGIN TRY
    BEGIN TRAN;

    EXECUTE AS USER = 'u_test_sales';

    EXEC sys.sp_executesql
        N'
        UPDATE dbo.PurchaseOrder
        SET purchase_status = ''CANCELLED''
        WHERE purchase_id = 2;
        ';

    REVERT;

    PRINT N'[FAIL] N1：销售店员竟然可以修改采购订单。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_sales'
        REVERT;

    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    PRINT N'[PASS] N1：销售店员越权修改采购订单被正确拒绝。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* ---------------------------------------------------------
   N2. 库存管理员试图读取会员数据

   预期：
   权限不足，操作失败。
   --------------------------------------------------------- */

PRINT N'========== N2：库存管理员越权读取会员信息 ==========';

BEGIN TRY

    EXECUTE AS USER = 'u_test_inventory';

    EXEC sys.sp_executesql
        N'
        SELECT *
        FROM dbo.Member;
        ';

    REVERT;

    PRINT N'[FAIL] N2：库存管理员竟然可以读取会员数据。';

END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_inventory'
        REVERT;

    PRINT N'[PASS] N2：库存管理员越权读取会员信息被正确拒绝。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* ---------------------------------------------------------
   N3. 销售店员试图直接修改库存数量

   预期：
   权限不足，操作失败。
   --------------------------------------------------------- */

PRINT N'========== N3：销售店员越权修改库存 ==========';

BEGIN TRY
    BEGIN TRAN;

    EXECUTE AS USER = 'u_test_sales';

    EXEC sys.sp_executesql
        N'
        UPDATE dbo.Inventory
        SET on_hand_qty = 999
        WHERE product_id = 1;
        ';

    REVERT;

    PRINT N'[FAIL] N3：销售店员竟然可以直接修改库存。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH

    IF USER_NAME() = N'u_test_sales'
        REVERT;

    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    PRINT N'[PASS] N3：销售店员越权修改库存被正确拒绝。';
    PRINT ERROR_MESSAGE();

END CATCH;
GO



/* =========================================================
   第九部分：角色与成员检查
   ========================================================= */

SELECT
    r.name AS database_role,
    m.name AS database_user
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS r
    ON drm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals AS m
    ON drm.member_principal_id = m.principal_id
WHERE r.name IN
(
    N'dbrole_sales_clerk',
    N'dbrole_inventory_manager',
    N'dbrole_store_manager'
)
ORDER BY r.name;
GO