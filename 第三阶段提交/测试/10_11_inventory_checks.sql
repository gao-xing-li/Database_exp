/* 在本库运行 baseline.sql 后运行本文件。结果集是预期与实际值的证据。 */
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3' OR @@TRANCOUNT <> 0
    THROW 53900, N'请在第三阶段专用库的新会话中运行。', 1;
DECLARE @p int = 90001301, @q int = 90001302;
IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 10 AND reserved_qty = 0 AND reorder_point = 12)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @q AND on_hand_qty = 8 AND reserved_qty = 0)
    THROW 53900, N'请先重置 P、Q 样例。', 1;

DECLARE @function_cases TABLE (scenario nvarchar(50), expected int NULL, actual int NULL);
INSERT @function_cases VALUES
    (N'P 补到警戒值', 2, dbo.RestockQuantity(@p, DEFAULT)),
    (N'Q 恰好达到警戒值', 0, dbo.RestockQuantity(@q, DEFAULT)),
    (N'P 已超过目标', 0, dbo.RestockQuantity(@p, 7)),
    (N'P 指定目标', 5, dbo.RestockQuantity(@p, 15)),
    (N'商品不存在', NULL, dbo.RestockQuantity(-1, DEFAULT)),
    (N'目标为负数', NULL, dbo.RestockQuantity(@p, -2147483648));
IF EXISTS (SELECT 1 FROM @function_cases WHERE ISNULL(expected, -1) <> ISNULL(actual, -1))
    THROW 53990, N'补货量断言失败。', 1;

-- 以 Web 库存账号的数据库权限运行实际入口，核对角色授权和同所有者的调用链。
IF USER_ID(N'course_stage3_inventory') IS NULL
    THROW 53900, N'找不到第三阶段 Web 库存角色用户，请完成初始化。', 1;
EXECUTE AS USER = 'course_stage3_inventory';
BEGIN TRY
    EXEC dbo.AdjustInventory @p, -2, N'盘点发现缺少 2 件', 2, 13;
    IF ISNULL(dbo.RestockQuantity(@p, DEFAULT), -1) <> 5
        THROW 53990, N'调减与修改警戒值后的补货量应为 5。', 1;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 8 AND reorder_point = 13)
   OR (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE product_id = @p) <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE product_id = @p AND business_type = 'ADJUSTMENT'
                  AND source_id > 0 AND employee_id = 2 AND reason = N'盘点发现缺少 2 件'
                  AND before_on_hand = 10 AND after_on_hand = 8 AND on_hand_delta = -2 AND operation_type = 'U')
    THROW 53990, N'有来源的手工调整或流水验证失败。', 1;
DECLARE @before_count int = (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE product_id = @p);
EXEC dbo.SetInventoryReorderPoint @p, 12;
IF @before_count <> (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE product_id = @p)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 8 AND reorder_point = 12)
    THROW 53990, N'独立修改警戒值不应增加数量流水。', 1;

UPDATE dbo.Inventory SET reserved_qty = 3 WHERE product_id = @p;
INSERT @function_cases VALUES (N'按可售 8 - 3 补到 12', 7, dbo.RestockQuantity(@p, DEFAULT));
IF EXISTS (SELECT 1 FROM @function_cases WHERE ISNULL(expected, -1) <> ISNULL(actual, -1))
    THROW 53990, N'补货量未扣除预留库存。', 1;
SELECT * FROM @function_cases;
SET @before_count = (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE product_id = @p);

DECLARE @invalid TABLE (
    scenario nvarchar(60), product_id int, delta int NULL, reason nvarchar(200),
    employee_id int, reorder_point int NULL, expected_error int
);
INSERT @invalid VALUES
    (N'商品不存在', -1, 2, N'测试', 2, NULL, 53101),
    (N'数量为零', @p, 0, N'测试', 2, NULL, 53102),
    (N'数量为空', @p, NULL, N'测试', 2, NULL, 53102),
    (N'原因为空', @p, 2, N'  ', 2, NULL, 53103),
    (N'员工不存在', @p, 2, N'测试', -1, NULL, 53104),
    (N'库存不得少于预留', @p, -6, N'测试', 2, NULL, 53105),
    (N'整数库存上限', @p, 2147483647, N'测试', 2, NULL, 53105),
    (N'负警戒值', @p, 2, N'测试', 2, -1, 53106);
DECLARE @scenario nvarchar(60), @product_id int, @delta int, @reason nvarchar(200),
        @employee_id int, @reorder_point int, @expected_error int;
DECLARE invalid_adjustments CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @invalid;
OPEN invalid_adjustments;
FETCH NEXT FROM invalid_adjustments INTO @scenario, @product_id, @delta, @reason, @employee_id, @reorder_point, @expected_error;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC dbo.AdjustInventory @product_id, @delta, @reason, @employee_id, @reorder_point;
        THROW 53990, N'非法调整意外成功。', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> @expected_error THROW;
        SELECT @scenario AS scenario, @expected_error AS expected_error, ERROR_NUMBER() AS actual_error,
               ERROR_MESSAGE() AS actual_message;
    END CATCH;
    FETCH NEXT FROM invalid_adjustments INTO @scenario, @product_id, @delta, @reason, @employee_id, @reorder_point, @expected_error;
END;
CLOSE invalid_adjustments;
DEALLOCATE invalid_adjustments;
IF @@TRANCOUNT <> 0 OR SESSION_CONTEXT(N'inventory_audit') IS NOT NULL
   OR @before_count <> (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE product_id = @p)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 8 AND reserved_qty = 3 AND reorder_point = 12)
    THROW 53990, N'失败后库存、流水、事务或上下文异常。', 1;

-- 用真实触发器演练 A 的来源传递，销售存储过程的正式联测由 A 合并后补齐。
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.SetInventoryAuditContext 'SALE', 1, 90013999;
    UPDATE dbo.Inventory SET on_hand_qty = on_hand_qty - 2 WHERE product_id IN (@p, @q);
    EXEC dbo.SetInventoryAuditContext;
    IF (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE business_type = 'SALE' AND source_id = 90013999
        AND employee_id = 1 AND on_hand_delta = -2) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE source_id = 90013999 AND product_id = @p
                      AND before_on_hand = 8 AND after_on_hand = 6 AND before_reserved = 3 AND after_reserved = 3)
       OR NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE source_id = 90013999 AND product_id = @q
                      AND before_on_hand = 8 AND after_on_hand = 6)
        THROW 53990, N'批量扣库应逐商品记带来源的流水。', 1;
    SELECT product_id, business_type, source_id, employee_id, before_on_hand, after_on_hand, on_hand_delta
    FROM dbo.InventoryAudit WHERE business_type = 'SALE' AND source_id = 90013999 ORDER BY product_id;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    EXEC dbo.SetInventoryAuditContext;
    THROW;
END CATCH;
IF EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE business_type = 'SALE' AND source_id = 90013999)
   OR (SELECT SUM(on_hand_qty) FROM dbo.Inventory WHERE product_id IN (@p, @q)) <> 16
    THROW 53990, N'回滚未同步清除库存变化与其流水。', 1;
SELECT N'批量扣库回滚' AS scenario, 16 AS expected_total, SUM(on_hand_qty) AS actual_total,
       (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE source_id = 90013999) AS sale_audit_rows
FROM dbo.Inventory WHERE product_id IN (@p, @q);

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @last_audit bigint = ISNULL((SELECT MAX(audit_id) FROM dbo.InventoryAudit), 0);
    DELETE dbo.Inventory WHERE product_id = @q;
    INSERT dbo.Inventory(product_id, on_hand_qty, reserved_qty, reorder_point) VALUES (@q, 8, 1, 8);
    UPDATE dbo.Inventory SET reserved_qty = 2 WHERE product_id = @q;
    IF NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE audit_id > @last_audit AND product_id = @q
                   AND operation_type = 'D' AND before_on_hand = 8 AND after_on_hand = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE audit_id > @last_audit AND product_id = @q
                      AND operation_type = 'I' AND before_on_hand = 0 AND after_on_hand = 8 AND reserved_delta = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE audit_id > @last_audit AND product_id = @q
                      AND operation_type = 'U' AND on_hand_delta = 0 AND reserved_delta = 1)
       OR EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE audit_id > @last_audit AND product_id = @q
                 AND (business_type <> 'DIRECT' OR LEN(sql_login) = 0))
        THROW 53990, N'直接增删库存行、修改预留量的流水不符合预期。', 1;
    SELECT product_id, business_type, employee_id, source_id, operation_type,
           before_on_hand, after_on_hand, reserved_delta
    FROM dbo.InventoryAudit WHERE audit_id > @last_audit AND product_id = @q ORDER BY audit_id;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
SELECT N'PASS' AS status, N'B 第 10–11 周库存调整、补货量、审计' AS suite;
