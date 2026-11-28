/* 第10周 B：库存调整；A 的销售统计过程在合并时加入本文件。 */
CREATE OR ALTER PROCEDURE dbo.SetInventoryAuditContext
    @business_type varchar(16) = NULL,
    @employee_id int = NULL,
    @source_id bigint = NULL,
    @reason nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @payload nvarchar(2000) = NULL;
    IF @business_type IS NOT NULL
    BEGIN
        IF @business_type NOT IN ('SALE', 'RESTOCK', 'ADJUSTMENT')
           OR @source_id IS NULL OR @source_id <= 0
           OR (@business_type = 'ADJUSTMENT' AND NULLIF(LTRIM(RTRIM(@reason)), N'') IS NULL)
           OR (@business_type <> 'ADJUSTMENT' AND @reason IS NOT NULL)
            THROW 53107, N'库存流水业务类型、来源或原因无效。', 1;
        IF NOT EXISTS (
            SELECT 1 FROM dbo.Employee WHERE employee_id = @employee_id AND employee_status = 'ACTIVE'
        )
            THROW 53104, N'操作员工不存在或已停用。', 1;
        SELECT @payload = (
            SELECT @business_type AS business_type, @employee_id AS employee_id,
                   @source_id AS source_id, @reason AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END;
    EXEC sys.sp_set_session_context @key = N'inventory_audit', @value = @payload;
END;
GO

-- 在调用事务中，先锁商品，再按主键锁定或补齐库存行。由业务过程调用。
CREATE OR ALTER PROCEDURE dbo.LockInventoryRow
    @product_id int
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Product WITH (UPDLOCK, HOLDLOCK, ROWLOCK) WHERE product_id = @product_id
    )
        THROW 53101, N'商品不存在。', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Inventory WITH (UPDLOCK, HOLDLOCK, ROWLOCK) WHERE product_id = @product_id
    )
        INSERT dbo.Inventory(product_id) VALUES (@product_id);
END;
GO

CREATE OR ALTER PROCEDURE dbo.AdjustInventory
    @product_id int,
    @delta int,
    @reason nvarchar(max),
    @employee_id int,
    @reorder_point int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;
    IF @delta IS NULL OR @delta = 0
        THROW 53102, N'调整数量必须为非零整数。', 1;
    DECLARE @clean_reason nvarchar(max) = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF @clean_reason IS NULL OR DATALENGTH(@clean_reason) > 400
        THROW 53103, N'请填写库存调整原因，最多200字。', 1;
    IF @reorder_point < 0
        THROW 53106, N'补货警戒值必须为非负整数。', 1;

    DECLARE @own_transaction bit = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @adjustment_id bigint, @audit_reason nvarchar(200) = @clean_reason;
    DECLARE @stock TABLE (
        product_id int, on_hand_qty int, reserved_qty int, reorder_point int, updated_at datetime2(7)
    );
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION AdjustInventory;
    BEGIN TRY
        SELECT @adjustment_id = NEXT VALUE FOR dbo.InventoryAdjustmentSeq;
        EXEC dbo.SetInventoryAuditContext 'ADJUSTMENT', @employee_id, @adjustment_id, @audit_reason;
        EXEC dbo.LockInventoryRow @product_id;
        UPDATE dbo.Inventory
        SET on_hand_qty = CONVERT(bigint, on_hand_qty) + @delta,
            reorder_point = COALESCE(@reorder_point, reorder_point),
            updated_at = SYSDATETIME()
        OUTPUT inserted.product_id, inserted.on_hand_qty, inserted.reserved_qty,
               inserted.reorder_point, inserted.updated_at INTO @stock
        WHERE product_id = @product_id
          AND CONVERT(bigint, on_hand_qty) + @delta BETWEEN reserved_qty AND 2147483647;
        IF @@ROWCOUNT <> 1
            THROW 53105, N'调整后库存不能少于预留库存或超出范围。', 1;
        EXEC dbo.SetInventoryAuditContext;
        IF @own_transaction = 1 COMMIT TRANSACTION;
        SELECT *, @adjustment_id AS adjustment_id FROM @stock;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION AdjustInventory;
        EXEC dbo.SetInventoryAuditContext;
        THROW;
    END CATCH;
END;
GO

-- 独立维护警戒值。数量没有变化，库存审计不会增加流水。
CREATE OR ALTER PROCEDURE dbo.SetInventoryReorderPoint
    @product_id int,
    @reorder_point int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;
    IF @reorder_point IS NULL OR @reorder_point < 0
        THROW 53106, N'补货警戒值必须为非负整数。', 1;
    DECLARE @own_transaction bit = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @stock TABLE (
        product_id int, on_hand_qty int, reserved_qty int, reorder_point int, updated_at datetime2(7)
    );
    IF @own_transaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION SetInventoryReorderPoint;
    BEGIN TRY
        EXEC dbo.LockInventoryRow @product_id;
        UPDATE dbo.Inventory
        SET reorder_point = @reorder_point, updated_at = SYSDATETIME()
        OUTPUT inserted.product_id, inserted.on_hand_qty, inserted.reserved_qty,
               inserted.reorder_point, inserted.updated_at INTO @stock
        WHERE product_id = @product_id;
        IF @own_transaction = 1 COMMIT TRANSACTION;
        SELECT * FROM @stock;
    END TRY
    BEGIN CATCH
        IF @own_transaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @own_transaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION SetInventoryReorderPoint;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON dbo.AdjustInventory TO web_manager, web_inventory;
GRANT EXECUTE ON dbo.SetInventoryReorderPoint TO web_manager, web_inventory;
GRANT EXECUTE ON dbo.SetInventoryAuditContext TO web_manager, web_clerk;
GO
