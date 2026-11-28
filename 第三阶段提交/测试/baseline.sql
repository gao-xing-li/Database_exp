/* 双会话实验的库存/补货基线。结束两个会话的事务后再执行。
   只重置下面明确保留的测试编号；销售草稿由 A 的脚本准备及重置。 */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3' OR @@TRANCOUNT <> 0
    THROW 53900, N'请在第三阶段专用库的新会话中重置基线。', 1;
IF OBJECT_ID(N'dbo.InventoryAudit', N'U') IS NULL
    THROW 53900, N'请先安装第三阶段库存对象。', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @products TABLE (product_id int PRIMARY KEY, code varchar(20), name nvarchar(150), stock int, target int);
    INSERT @products VALUES (90001301, 'W13-P', N'并发样例 P', 10, 12), (90001302, 'W13-Q', N'并发样例 Q', 8, 8);
    DECLARE @purchases TABLE (purchase_id int PRIMARY KEY, code varchar(20));
    INSERT @purchases VALUES (90013101, 'W13-R-P'), (90013102, 'W13-R-PQ'), (90013103, 'W13-R-EMPTY'),
                             (90013104, 'W13-R-DRAFT'), (90013105, 'W13-R-PARTIAL');
    DECLARE @categories TABLE (category_id int PRIMARY KEY, name nvarchar(50), parent int NULL);
    INSERT @categories VALUES (90001201, N'实验分类 · 周边', NULL), (90001202, N'实验分类 · 展示类', 90001201),
        (90001203, N'实验分类 · 亚克力立牌', 90001202), (90001204, N'实验分类 · 随身类', 90001201),
        (90001205, N'实验分类 · 钥匙扣', 90001204);

    IF EXISTS (SELECT 1 FROM dbo.Product p JOIN @products s ON s.product_id = p.product_id WHERE p.product_code <> s.code)
       OR EXISTS (SELECT 1 FROM dbo.PurchaseOrder p JOIN @purchases s ON s.purchase_id = p.purchase_id
                  WHERE p.purchase_no <> s.code OR p.purchase_type <> 'RESTOCK')
       OR EXISTS (SELECT 1 FROM dbo.ProductCategory c JOIN @categories s ON s.category_id = c.category_id
                  WHERE c.category_name <> s.name)
        THROW 53900, N'测试编号被其他业务占用，基线未改写。', 1;

    EXEC dbo.SetInventoryAuditContext;
    INSERT dbo.ProductCategory(category_id, category_name)
    SELECT s.category_id, s.name FROM @categories s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.ProductCategory c WHERE c.category_id = s.category_id);
    UPDATE c SET c.parent_category_id = s.parent
    FROM dbo.ProductCategory c JOIN @categories s ON s.category_id = c.category_id;
    INSERT dbo.Product(product_id, product_code, product_name, category_id, sale_price)
    SELECT s.product_id, s.code, s.name, 90001203, 12.50 FROM @products s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Product p WHERE p.product_id = s.product_id);
    UPDATE p SET p.sale_price = 12.50, p.product_status = 'ON_SALE'
    FROM dbo.Product p JOIN @products s ON s.product_id = p.product_id;
    INSERT dbo.Inventory(product_id)
    SELECT s.product_id FROM @products s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.product_id = s.product_id);
    UPDATE i SET i.on_hand_qty = s.stock, i.reserved_qty = 0, i.reorder_point = s.target, i.updated_at = SYSDATETIME()
    FROM dbo.Inventory i JOIN @products s ON s.product_id = i.product_id;
    DELETE a FROM dbo.InventoryAudit a JOIN @products s ON s.product_id = a.product_id;

    DELETE i FROM dbo.PurchaseOrderItem i JOIN @purchases s ON i.purchase_id = s.purchase_id;
    DELETE p FROM dbo.PurchaseOrder p JOIN @purchases s ON p.purchase_id = s.purchase_id;
    INSERT dbo.PurchaseOrder(purchase_id, purchase_no, supplier_id, purchase_type, created_by, purchase_status)
    SELECT purchase_id, code, 1, 'RESTOCK', 3, IIF(purchase_id = 90013104, 'CREATED', 'ORDERED') FROM @purchases;
    INSERT dbo.PurchaseOrderItem(purchase_id, product_id, ordered_qty, unit_cost, received_qty)
    VALUES (90013101, 90001301, 5, 5, 0),
           (90013102, 90001302, 3, 5, 0), (90013102, 90001301, 5, 5, 0),
           (90013104, 90001301, 1, 5, 0), (90013105, 90001301, 5, 5, 1);
    COMMIT TRANSACTION;
    SELECT p.code AS product_code, i.product_id, i.on_hand_qty, i.reserved_qty, i.reorder_point
    FROM dbo.Inventory i JOIN @products p ON p.product_id = i.product_id ORDER BY i.product_id;
    SELECT p.purchase_id, p.purchase_no, p.purchase_status, i.product_id, i.ordered_qty, i.received_qty
    FROM dbo.PurchaseOrder p JOIN @purchases s ON s.purchase_id = p.purchase_id
    LEFT JOIN dbo.PurchaseOrderItem i ON i.purchase_id = p.purchase_id ORDER BY p.purchase_id, i.product_id;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
