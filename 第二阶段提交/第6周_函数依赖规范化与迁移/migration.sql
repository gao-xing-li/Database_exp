/* 第六周：v0.1 -> 第六周目标结构。UTF-8；在 SSMS 选中实验副本执行。
   前提：第一阶段 00—07 已形成完整基线；先保存数据库副本。
   不含 USE，避免连接实验副本后又切回原库。当前库名必须含 Week6。
   只修改 PurchaseOrder 的一个索引和两个 CHECK；保留所有业务数据。
   一次迁移：成功后如需重演，从原 v0.1 基线重新取得副本。
   冲突不自动修正；失败由事务回滚，原始错误继续抛出。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF DB_NAME() NOT LIKE N'%Week6%'
    THROW 51000, N'请连接名称含 Week6 的独立实验副本，禁止直接迁移原业务库。', 1;
IF @@TRANCOUNT <> 0
    THROW 51001, N'请在没有外层事务的会话中执行本迁移。', 1;

BEGIN TRY
    BEGIN TRAN;

    -- 核对课程基线对象；不擅自初始化、重建或补齐缺失对象。
    DECLARE @Tables TABLE (name sysname PRIMARY KEY);
    INSERT @Tables VALUES
      (N'ProductCategory'),(N'AnimeIP'),(N'CharacterInfo'),(N'Product'),
      (N'Inventory'),(N'Member'),(N'BusinessRole'),(N'Employee'),(N'Supplier'),
      (N'SalesOrder'),(N'SalesOrderItem'),(N'PresaleActivity'),
      (N'PresaleReservation'),(N'PurchaseOrder'),(N'PurchaseOrderItem');
    IF EXISTS (SELECT 1 FROM @Tables WHERE OBJECT_ID(N'dbo.' + name,N'U') IS NULL)
        THROW 51002, N'缺少 v0.1 业务表，停止迁移。', 1;
    IF OBJECT_ID(N'dbo.vw_OrderDetail',N'V') IS NULL
       OR OBJECT_ID(N'dbo.vw_ProductSalesSummary',N'V') IS NULL
       OR OBJECT_ID(N'dbo.vw_InventoryStatus',N'V') IS NULL
       OR OBJECT_ID(N'dbo.vw_MemberConsumptionSummary',N'V') IS NULL
       OR DATABASE_PRINCIPAL_ID(N'dbrole_sales_clerk') IS NULL
       OR DATABASE_PRINCIPAL_ID(N'dbrole_inventory_manager') IS NULL
       OR DATABASE_PRINCIPAL_ID(N'dbrole_store_manager') IS NULL
        THROW 51003, N'缺少 v0.1 视图或角色，请先准备完整基线。', 1;
    IF COL_LENGTH(N'dbo.Product',N'ip_id') IS NULL
       OR COL_LENGTH(N'dbo.Product',N'character_id') IS NULL
       OR COL_LENGTH(N'dbo.PurchaseOrderItem',N'received_qty') IS NULL
       OR COL_LENGTH(N'dbo.SalesOrderItem',N'unit_price') IS NULL
       OR COL_LENGTH(N'dbo.PresaleActivity',N'decision_demand_qty') IS NULL
       OR COL_LENGTH(N'dbo.PresaleActivity',N'planned_purchase_qty') IS NULL
        THROW 51004, N'基线缺少本轮确认保留的字段。', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE parent_object_id=OBJECT_ID(N'dbo.PurchaseOrder')
                     AND name=N'CK_PurchaseOrder_PresaleRequired'
                     AND is_disabled=0 AND is_not_trusted=0)
       OR NOT EXISTS (SELECT 1 FROM sys.check_constraints
                      WHERE parent_object_id=OBJECT_ID(N'dbo.PurchaseOrder')
                        AND name=N'CK_PurchaseOrder_Status'
                        AND definition LIKE N'%PARTIAL_RECEIVED%'
                        AND is_disabled=0 AND is_not_trusted=0)
        THROW 51005, N'采购约束不符合预期 v0.1，可能已迁移或结构不同。', 1;
    IF EXISTS (SELECT 1 FROM sys.indexes
                WHERE object_id=OBJECT_ID(N'dbo.PurchaseOrder')
                  AND name=N'UX_PurchaseOrder_PresaleID')
       OR OBJECT_ID(N'dbo.CK_PurchaseOrder_TypePresale',N'C') IS NOT NULL
        THROW 51006, N'目标对象已存在；请使用未迁移的 v0.1 副本。', 1;

    -- 在检查与改结构之间保持采购表稳定，避免冲突检查后又被并发写入。
    DECLARE @Rows bigint;
    SELECT @Rows=COUNT_BIG(*) FROM dbo.PurchaseOrder WITH (TABLOCKX,HOLDLOCK);
    DECLARE @Conflict TABLE
      (reason nvarchar(80), purchase_id int, purchase_no varchar(20),
       purchase_type varchar(20), presale_id int NULL, purchase_status varchar(30));
    INSERT @Conflict
    SELECT N'同活动关联多张采购单',purchase_id,purchase_no,purchase_type,presale_id,purchase_status
    FROM dbo.PurchaseOrder
    WHERE presale_id IN (SELECT presale_id FROM dbo.PurchaseOrder
                         WHERE presale_id IS NOT NULL GROUP BY presale_id HAVING COUNT(*)>1);
    INSERT @Conflict
    SELECT N'采购类型与活动关联冲突',purchase_id,purchase_no,purchase_type,presale_id,purchase_status
    FROM dbo.PurchaseOrder
    WHERE (purchase_type='RESTOCK' AND presale_id IS NOT NULL)
       OR (purchase_type='PRESALE' AND presale_id IS NULL)
       OR purchase_type NOT IN ('RESTOCK','PRESALE');
    INSERT @Conflict
    SELECT N'状态不属于目标状态域',purchase_id,purchase_no,purchase_type,presale_id,purchase_status
    FROM dbo.PurchaseOrder
    WHERE purchase_status NOT IN ('CREATED','ORDERED','RECEIVED','CANCELLED');
    IF EXISTS (SELECT 1 FROM @Conflict)
    BEGIN
        SELECT * FROM @Conflict ORDER BY purchase_id,reason;
        THROW 51007, N'存在迁移冲突；已列出记录，未自动改写任何业务数据。', 1;
    END;

    CREATE UNIQUE INDEX UX_PurchaseOrder_PresaleID
      ON dbo.PurchaseOrder(presale_id) WHERE presale_id IS NOT NULL;
    ALTER TABLE dbo.PurchaseOrder DROP CONSTRAINT CK_PurchaseOrder_PresaleRequired;
    ALTER TABLE dbo.PurchaseOrder WITH CHECK
      ADD CONSTRAINT CK_PurchaseOrder_TypePresale CHECK
      ((purchase_type='PRESALE' AND presale_id IS NOT NULL)
        OR (purchase_type='RESTOCK' AND presale_id IS NULL));
    ALTER TABLE dbo.PurchaseOrder DROP CONSTRAINT CK_PurchaseOrder_Status;
    ALTER TABLE dbo.PurchaseOrder WITH CHECK
      ADD CONSTRAINT CK_PurchaseOrder_Status CHECK
      (purchase_status IN ('CREATED','ORDERED','RECEIVED','CANCELLED'));

    COMMIT;
    SELECT N'PASS' AS status,DB_NAME() AS target_database,@Rows AS purchase_rows,
           N'新增活动唯一索引；替换类型关联和状态 CHECK；业务数据未改写' AS result;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
