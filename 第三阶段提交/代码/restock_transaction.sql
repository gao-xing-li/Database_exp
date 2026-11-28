/* 第12周 B：按已有 RESTOCK 采购单整单人工验收。 */
CREATE OR ALTER PROCEDURE dbo.ReceiveRestock
    @purchase_id int,
    @employee_id int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;
    DECLARE @own_transaction bit = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @kind varchar(20), @status varchar(30), @order_time datetime2(7), @received_time datetime2(7);
    DECLARE @product_id int, @qty int, @item_count int;
    DECLARE @items TABLE (product_id int PRIMARY KEY, ordered_qty int NOT NULL, received_qty int NOT NULL);

    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION ReceiveRestock;
    BEGIN TRY
        SELECT @kind = purchase_type, @status = purchase_status, @order_time = order_time
        FROM dbo.PurchaseOrder WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
        WHERE purchase_id = @purchase_id;
        IF @status IS NULL
            THROW 53110, N'补货单不存在。', 1;
        IF @kind <> 'RESTOCK'
            THROW 53111, N'此入口只验收补货采购单。', 1;
        IF @status = 'RECEIVED'
            THROW 53112, N'补货单已入库。', 1;
        IF @status <> 'ORDERED'
            THROW 53113, N'仅已向供应商下单的补货单可入库。', 1;

        INSERT @items(product_id, ordered_qty, received_qty)
        SELECT product_id, ordered_qty, received_qty
        FROM dbo.PurchaseOrderItem WITH (UPDLOCK, HOLDLOCK)
        WHERE purchase_id = @purchase_id;
        SET @item_count = @@ROWCOUNT;
        IF @item_count = 0 OR EXISTS (SELECT 1 FROM @items WHERE ordered_qty <= 0 OR received_qty <> 0)
            THROW 53114, N'补货单须有正数量明细，且全部尚未入库。', 1;
        IF @order_time > SYSDATETIME()
            THROW 53115, N'下单时间晚于当前时间，无法验收。', 1;

        EXEC dbo.SetInventoryAuditContext 'RESTOCK', @employee_id, @purchase_id;
        -- ORDER BY 决定逐个主键加锁的顺序；一条批量 UPDATE 的执行计划不承诺此顺序。
        DECLARE receipt_items CURSOR LOCAL FAST_FORWARD FOR
            SELECT product_id, ordered_qty FROM @items ORDER BY product_id;
        OPEN receipt_items;
        FETCH NEXT FROM receipt_items INTO @product_id, @qty;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.LockInventoryRow @product_id;
            UPDATE dbo.Inventory
            SET on_hand_qty = CONVERT(bigint, on_hand_qty) + @qty, updated_at = SYSDATETIME()
            WHERE product_id = @product_id AND on_hand_qty <= 2147483647 - @qty;
            IF @@ROWCOUNT <> 1
                THROW 53105, N'补货后库存超出范围。', 1;
            FETCH NEXT FROM receipt_items INTO @product_id, @qty;
        END;
        CLOSE receipt_items;
        DEALLOCATE receipt_items;
        EXEC dbo.SetInventoryAuditContext;

        UPDATE dbo.PurchaseOrderItem
        SET received_qty = ordered_qty
        WHERE purchase_id = @purchase_id;
        SET @received_time = SYSDATETIME();
        UPDATE dbo.PurchaseOrder
        SET purchase_status = 'RECEIVED', received_time = @received_time, received_by = @employee_id
        WHERE purchase_id = @purchase_id;
        IF @own_transaction = 1 COMMIT TRANSACTION;
        SELECT @purchase_id AS purchase_id, 'RECEIVED' AS purchase_status,
               @received_time AS received_time, @employee_id AS received_by, @item_count AS item_count;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION ReceiveRestock;
        EXEC dbo.SetInventoryAuditContext;
        THROW;
    END CATCH;
END;
GO
