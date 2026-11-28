/* 第11周 B：库存审计；A 的订单触发器在合并时加入本文件。 */
CREATE OR ALTER TRIGGER dbo.TR_Inventory_Audit
ON dbo.Inventory
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    IF ROWCOUNT_BIG() = 0 RETURN;
    SET NOCOUNT ON;

    DECLARE @payload nvarchar(2000) = CONVERT(nvarchar(2000), SESSION_CONTEXT(N'inventory_audit'));
    DECLARE @business_type varchar(16) = 'DIRECT', @employee_id int, @source_id bigint, @reason nvarchar(200);
    IF @payload IS NOT NULL
    BEGIN
        IF ISJSON(@payload) <> 1
            THROW 53107, N'库存流水上下文格式无效。', 1;
        SELECT @business_type = JSON_VALUE(@payload, '$.business_type'),
               @employee_id = TRY_CONVERT(int, JSON_VALUE(@payload, '$.employee_id')),
               @source_id = TRY_CONVERT(bigint, JSON_VALUE(@payload, '$.source_id')),
               @reason = JSON_VALUE(@payload, '$.reason');
        IF @business_type IS NULL OR @business_type NOT IN ('SALE', 'RESTOCK', 'ADJUSTMENT')
            THROW 53107, N'库存流水业务类型无效。', 1;
    END;

    INSERT dbo.InventoryAudit (
        product_id, operation_type, business_type, source_id, employee_id, reason,
        before_on_hand, after_on_hand, before_reserved, after_reserved, sql_login
    )
    SELECT COALESCE(i.product_id, d.product_id),
           CASE WHEN d.product_id IS NULL THEN 'I' WHEN i.product_id IS NULL THEN 'D' ELSE 'U' END,
           @business_type, @source_id, @employee_id, @reason,
           COALESCE(d.on_hand_qty, 0), COALESCE(i.on_hand_qty, 0),
           COALESCE(d.reserved_qty, 0), COALESCE(i.reserved_qty, 0), ORIGINAL_LOGIN()
    FROM inserted AS i
    FULL OUTER JOIN deleted AS d ON d.product_id = i.product_id
    WHERE COALESCE(d.on_hand_qty, 0) <> COALESCE(i.on_hand_qty, 0)
       OR COALESCE(d.reserved_qty, 0) <> COALESCE(i.reserved_qty, 0);
END;
GO
