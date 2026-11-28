/* 重跑 baseline.sql 后执行。仅在本库、两个并发会话均已结束的前提下运行。 */
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3' OR @@TRANCOUNT <> 0
    THROW 53900, N'请在第三阶段专用库的新会话中运行。', 1;
DECLARE @p int = 90001301, @q int = 90001302, @success int = 90013101, @failure int = 90013102;
IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 10 AND reserved_qty = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @q AND on_hand_qty = 8 AND reserved_qty = 0)
   OR (SELECT COUNT(*) FROM dbo.PurchaseOrder WHERE purchase_id IN (@success, @failure) AND purchase_status = 'ORDERED') <> 2
    THROW 53900, N'请先重置测试补货单与 P、Q 样例。', 1;

SELECT SERVERPROPERTY('ProductVersion') AS sql_version, DB_NAME() AS database_name, is_read_committed_snapshot_on
FROM sys.databases WHERE database_id = DB_ID();

EXEC dbo.ReceiveRestock @success, 2;
IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 15 AND reserved_qty = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE purchase_id = @success AND purchase_status = 'RECEIVED'
                  AND received_by = 2 AND received_time >= order_time)
   OR NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrderItem WHERE purchase_id = @success AND product_id = @p AND received_qty = 5)
   OR (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @success
       AND employee_id = 2 AND product_id = @p AND before_on_hand = 10 AND after_on_hand = 15 AND on_hand_delta = 5) <> 1
    THROW 53990, N'补货事务提交不完整。', 1;
SELECT N'提交' AS scenario, i.on_hand_qty, o.purchase_id, o.purchase_status, o.received_time, o.received_by, r.received_qty,
       a.before_on_hand, a.after_on_hand, a.on_hand_delta
FROM dbo.PurchaseOrder o JOIN dbo.PurchaseOrderItem r ON r.purchase_id = o.purchase_id
JOIN dbo.Inventory i ON i.product_id = r.product_id
JOIN dbo.InventoryAudit a ON a.source_id = o.purchase_id AND a.business_type = 'RESTOCK'
WHERE o.purchase_id = @success;

DECLARE @invalid TABLE (scenario nvarchar(60), purchase_id int, employee_id int, expected_error int);
INSERT @invalid VALUES
    (N'不存在', -1, 2, 53110), (N'重复入库', @success, 2, 53112),
    (N'草稿未下单', 90013104, 2, 53113), (N'无明细', 90013103, 2, 53114),
    (N'已有验收量', 90013105, 2, 53114), (N'员工不存在', @failure, -1, 53104);
DECLARE @scenario nvarchar(60), @purchase_id int, @employee_id int, @expected_error int;
DECLARE invalid_receipts CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @invalid;
OPEN invalid_receipts;
FETCH NEXT FROM invalid_receipts INTO @scenario, @purchase_id, @employee_id, @expected_error;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC dbo.ReceiveRestock @purchase_id, @employee_id;
        THROW 53990, N'非法入库意外成功。', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> @expected_error THROW;
        SELECT @scenario AS scenario, @expected_error AS expected_error, ERROR_NUMBER() AS actual_error, ERROR_MESSAGE() AS actual_message;
    END CATCH;
    FETCH NEXT FROM invalid_receipts INTO @scenario, @purchase_id, @employee_id, @expected_error;
END;
CLOSE invalid_receipts;
DEALLOCATE invalid_receipts;
IF @@TRANCOUNT <> 0 OR SESSION_CONTEXT(N'inventory_audit') IS NOT NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 15)
   OR (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @success) <> 1
    THROW 53990, N'重复入库或非法输入留下了变更。', 1;
BEGIN TRY
    UPDATE dbo.PurchaseOrderItem SET ordered_qty = 0 WHERE purchase_id = @failure AND product_id = @p;
    THROW 53990, N'数据库意外允许非正订购数量。', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 547 THROW;
    SELECT N'订购数量为零' AS scenario, 547 AS expected_error, ERROR_NUMBER() AS actual_error;
END CATCH;

-- 不修改生产过程。令编号较大的 Q 入库时超出 int，P 的库存及流水已经写入。
UPDATE dbo.Inventory SET on_hand_qty = 2147483646 WHERE product_id = @q;
BEGIN TRY
    EXEC dbo.ReceiveRestock @failure, 2;
    THROW 53990, N'第二项超限的入库意外成功。', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 53105 THROW;
    SELECT N'P 写入后，Q 超限回滚' AS scenario, 53105 AS expected_error,
           ERROR_NUMBER() AS actual_error, ERROR_MESSAGE() AS actual_message;
END CATCH;
-- 单独读取事务状态，避免表查询自身的自动提交事务影响 XACT_STATE()。
DECLARE @state_after_failure int = XACT_STATE();
IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 15)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @q AND on_hand_qty = 2147483646)
   OR NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE purchase_id = @failure AND purchase_status = 'ORDERED'
                  AND received_time IS NULL AND received_by IS NULL)
   OR EXISTS (SELECT 1 FROM dbo.PurchaseOrderItem WHERE purchase_id = @failure AND received_qty <> 0)
   OR EXISTS (SELECT 1 FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @failure)
   OR @state_after_failure <> 0 OR SESSION_CONTEXT(N'inventory_audit') IS NOT NULL
    THROW 53990, N'中途失败留下不完整数据。', 1;
SELECT N'失败后的数据' AS scenario, i.product_id, i.on_hand_qty, r.received_qty, o.purchase_status,
       o.received_time, o.received_by, @state_after_failure AS transaction_state,
       (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @failure) AS audit_count
FROM dbo.PurchaseOrder o JOIN dbo.PurchaseOrderItem r ON o.purchase_id = r.purchase_id
JOIN dbo.Inventory i ON i.product_id = r.product_id
WHERE o.purchase_id = @failure ORDER BY i.product_id;

-- 恢复正常 Q 后重试同一失败单据，验证可以完整入库且两行流水使用同一单号。
UPDATE dbo.Inventory SET on_hand_qty = 8 WHERE product_id = @q;
EXEC dbo.ReceiveRestock @failure, 2;
IF (SELECT COUNT(*) FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @failure AND employee_id = 2) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @p AND on_hand_qty = 20)
   OR NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE product_id = @q AND on_hand_qty = 11)
   OR (SELECT COUNT(*) FROM dbo.PurchaseOrderItem WHERE purchase_id = @failure AND received_qty = ordered_qty) <> 2
    THROW 53990, N'修正后重试未完整入库。', 1;
SELECT product_id, source_id, employee_id, before_on_hand, after_on_hand, on_hand_delta
FROM dbo.InventoryAudit WHERE business_type = 'RESTOCK' AND source_id = @failure ORDER BY product_id;
SELECT N'PASS' AS status, N'B 第 12 周补货事务' AS suite;
