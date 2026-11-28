/* 第三阶段库存增量。通过 prepare_stage3.py 装到独立样例库。 */
SET XACT_ABORT ON;
GO
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3'
    THROW 53100, N'请选择第三阶段专用测试库。', 1;
IF OBJECT_ID(N'dbo.WebUser', N'U') IS NULL
    THROW 53100, N'请先准备 v1.0 Web 数据库结构。', 1;
GO
IF OBJECT_ID(N'dbo.InventoryAudit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.InventoryAudit (
        audit_id bigint IDENTITY PRIMARY KEY,
        product_id int NOT NULL,
        operation_type char(1) NOT NULL,
        business_type varchar(16) NOT NULL,
        source_id bigint NULL,
        employee_id int NULL REFERENCES dbo.Employee(employee_id),
        reason nvarchar(200) NULL,
        before_on_hand int NOT NULL,
        after_on_hand int NOT NULL,
        before_reserved int NOT NULL,
        after_reserved int NOT NULL,
        on_hand_delta AS (after_on_hand - before_on_hand),
        reserved_delta AS (after_reserved - before_reserved),
        changed_at datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
        sql_login sysname NOT NULL,
        CONSTRAINT CK_InventoryAudit_Operation CHECK (operation_type IN ('I', 'U', 'D')),
        CONSTRAINT CK_InventoryAudit_Source CHECK (
            (business_type = 'DIRECT' AND source_id IS NULL AND employee_id IS NULL AND reason IS NULL)
            OR (business_type IN ('SALE', 'RESTOCK', 'ADJUSTMENT')
                AND source_id IS NOT NULL AND source_id > 0 AND employee_id IS NOT NULL
                AND ((business_type = 'ADJUSTMENT' AND reason IS NOT NULL)
                  OR (business_type <> 'ADJUSTMENT' AND reason IS NULL)))
        )
    );
    CREATE INDEX IX_InventoryAudit_Source
        ON dbo.InventoryAudit(business_type, source_id, product_id);
END;
IF OBJECT_ID(N'dbo.InventoryAdjustmentSeq', N'SO') IS NULL
    CREATE SEQUENCE dbo.InventoryAdjustmentSeq AS bigint START WITH 1 INCREMENT BY 1;
GO
