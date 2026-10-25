/* 第六周回归：在已迁移的 Week6 副本执行；基线库仅 SELECT。
   先保留完整 v0.1 基线，再取得目标副本并运行 migration.sql。
   修改下面唯一的基线库名；目标库由 SSMS 当前连接决定，不含 USE。
   基线和目标应位于同一实例；执行者需能读取两库并 EXECUTE AS 测试用户。
   不硬编码样例金额作为前后基准，不创建永久测试表。
*/
SET NOCOUNT ON;
SET XACT_ABORT OFF; -- 故意触发约束错误后，测试事务仍由 CATCH 统一回滚。
-- 过滤索引的写入要求这些会话选项；新查询窗口不继承迁移会话的 SET。
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
DROP TABLE IF EXISTS #Result;
DROP TABLE IF EXISTS #Metadata;
DROP TABLE IF EXISTS #Cases;
DECLARE @BaselineDatabase sysname=N'AnimeGoodsStoreDB_Week6Baseline';
IF DB_NAME() NOT LIKE N'%Week6%' OR DB_NAME()=@BaselineDatabase
    THROW 51100,N'请在已迁移的 Week6 目标副本执行，基线库必须不同。',1;
IF DB_ID(@BaselineDatabase) IS NULL OR @@TRANCOUNT<>0
    THROW 51101,N'基线库不存在或会话已有事务。',1;

CREATE TABLE #Result
 (test_id varchar(50) PRIMARY KEY, expected nvarchar(300), actual nvarchar(4000), status varchar(4));
DECLARE @Ref nvarchar(258)=QUOTENAME(@BaselineDatabase),@Sql nvarchar(max),
        @Table sysname,@Mismatch bit,@Count bigint,@Before bigint;
DECLARE @Tables TABLE(name sysname PRIMARY KEY);
INSERT @Tables VALUES
 (N'ProductCategory'),(N'AnimeIP'),(N'CharacterInfo'),(N'Product'),(N'Inventory'),
 (N'Member'),(N'BusinessRole'),(N'Employee'),(N'Supplier'),(N'SalesOrder'),
 (N'SalesOrderItem'),(N'PresaleActivity'),(N'PresaleReservation'),
 (N'PurchaseOrder'),(N'PurchaseOrderItem');

-- 每表全部列双向 EXCEPT，结合主键唯一性和行数检查；可空值按集合语义比较。
DECLARE tables_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @Tables ORDER BY name;
OPEN tables_cursor;
FETCH NEXT FROM tables_cursor INTO @Table;
WHILE @@FETCH_STATUS=0
BEGIN
    IF OBJECT_ID(N'dbo.'+@Table,N'U') IS NULL
        THROW 51102,N'目标副本缺少预期业务表。',1;
    SET @Sql=N'SELECT @b=COUNT_BIG(*) FROM '+@Ref+N'.dbo.'+QUOTENAME(@Table)+N';
      SELECT @a=COUNT_BIG(*) FROM dbo.'+QUOTENAME(@Table)+N';
      SELECT @m=CASE WHEN EXISTS(SELECT * FROM '+@Ref+N'.dbo.'+QUOTENAME(@Table)+N'
        EXCEPT SELECT * FROM dbo.'+QUOTENAME(@Table)+N')
        OR EXISTS(SELECT * FROM dbo.'+QUOTENAME(@Table)+N'
        EXCEPT SELECT * FROM '+@Ref+N'.dbo.'+QUOTENAME(@Table)+N') THEN 1 ELSE 0 END;';
    EXEC sys.sp_executesql @Sql,N'@a bigint OUTPUT,@b bigint OUTPUT,@m bit OUTPUT',
         @Count OUTPUT,@Before OUTPUT,@Mismatch OUTPUT;
    INSERT #Result VALUES('DATA_'+@Table,N'全部列及行数与 v0.1 一致',
      CONCAT(N'基线=',@Before,N'；迁移后=',@Count,N'；内容差异=',@Mismatch),
      IIF(@Mismatch=0 AND @Count=@Before,'PASS','FAIL'));
    FETCH NEXT FROM tables_cursor INTO @Table;
END;
CLOSE tables_cursor; DEALLOCATE tables_cursor;

-- 用原视图核对订单明细、销量、库存及会员统计；单独比较订单金额。
DECLARE @Queries TABLE(name sysname,query nvarchar(max));
INSERT @Queries VALUES
 (N'ORDER_DETAIL',N'SELECT * FROM {DB}dbo.vw_OrderDetail'),
 (N'SALES',N'SELECT * FROM {DB}dbo.vw_ProductSalesSummary'),
 (N'INVENTORY',N'SELECT * FROM {DB}dbo.vw_InventoryStatus'),
 (N'MEMBER',N'SELECT * FROM {DB}dbo.vw_MemberConsumptionSummary'),
 (N'ORDER_AMOUNT',N'SELECT so.order_id,COUNT(i.product_id) AS item_count,
   COALESCE(SUM(i.quantity*i.unit_price),0) AS amount FROM {DB}dbo.SalesOrder so
   LEFT JOIN {DB}dbo.SalesOrderItem i ON i.order_id=so.order_id GROUP BY so.order_id');
DECLARE @Name sysname,@Query nvarchar(max),@BQuery nvarchar(max),@AQuery nvarchar(max);
DECLARE queries_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name,query FROM @Queries;
OPEN queries_cursor; FETCH NEXT FROM queries_cursor INTO @Name,@Query;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @BQuery=REPLACE(@Query,N'{DB}',@Ref+N'.');
    SET @AQuery=REPLACE(@Query,N'{DB}',N'');
    SET @Sql=N'SELECT @m=CASE WHEN EXISTS('+@BQuery+N' EXCEPT '+@AQuery+N')
     OR EXISTS('+@AQuery+N' EXCEPT '+@BQuery+N') THEN 1 ELSE 0 END;';
    EXEC sys.sp_executesql @Sql,N'@m bit OUTPUT',@Mismatch OUTPUT;
    INSERT #Result VALUES('QUERY_'+@Name,N'双向差集为空',CONCAT(N'内容差异=',@Mismatch),
                          IIF(@Mismatch=0,'PASS','FAIL'));
    FETCH NEXT FROM queries_cursor INTO @Name,@Query;
END;
CLOSE queries_cursor; DEALLOCATE queries_cursor;

-- 对比保留的结构与权限；仅排除本周计划修改的三个对象。
CREATE TABLE #Metadata(scope varchar(8),kind varchar(20),object_name nvarchar(300),value nvarchar(max));
DECLARE @MetadataSql nvarchar(max)=N'
 INSERT #Metadata
 SELECT @scope,''COLUMN'',CONCAT(s.name,''.'',t.name,''.'',c.name),
   CONCAT(c.column_id,''|'',TYPE_NAME(c.user_type_id),''|'',c.max_length,''|'',c.precision,
    ''|'',c.scale,''|'',c.is_nullable,''|'',c.is_identity,''|'',c.collation_name,''|'',dc.definition)
 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id
 JOIN sys.columns c ON c.object_id=t.object_id
 LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id
 WHERE s.name=''dbo'' AND t.is_ms_shipped=0;
 INSERT #Metadata
 SELECT @scope,''CHECK'',CONCAT(OBJECT_SCHEMA_NAME(parent_object_id),''.'',name),
    CONCAT(definition,''|'',is_disabled,''|'',is_not_trusted) FROM sys.check_constraints
 WHERE name NOT IN (''CK_PurchaseOrder_PresaleRequired'',''CK_PurchaseOrder_TypePresale'',''CK_PurchaseOrder_Status'');
 INSERT #Metadata
 SELECT @scope,''FK'',CONCAT(OBJECT_SCHEMA_NAME(f.parent_object_id),''.'',f.name,''.'',fc.constraint_column_id),
  CONCAT(OBJECT_NAME(f.parent_object_id),''.'',COL_NAME(fc.parent_object_id,fc.parent_column_id),''->'',
    OBJECT_SCHEMA_NAME(f.referenced_object_id),''.'',OBJECT_NAME(f.referenced_object_id),''.'',
    COL_NAME(fc.referenced_object_id,fc.referenced_column_id),''|'',f.delete_referential_action,
    ''|'',f.update_referential_action,''|'',f.is_disabled,''|'',f.is_not_trusted)
 FROM sys.foreign_keys f JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id;
 INSERT #Metadata
 SELECT @scope,''INDEX'',CONCAT(OBJECT_SCHEMA_NAME(i.object_id),''.'',OBJECT_NAME(i.object_id),''.'',i.name,''.'',ic.index_column_id),
  CONCAT(i.is_unique,''|'',i.is_primary_key,''|'',i.is_unique_constraint,''|'',i.filter_definition,
    ''|'',COL_NAME(ic.object_id,ic.column_id),''|'',ic.key_ordinal,''|'',ic.is_descending_key,''|'',ic.is_included_column)
 FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
 WHERE OBJECTPROPERTY(i.object_id,''IsUserTable'')=1 AND i.name<>''UX_PurchaseOrder_PresaleID'';
 INSERT #Metadata
 SELECT @scope,''VIEW'',CONCAT(SCHEMA_NAME(schema_id),''.'',name),OBJECT_DEFINITION(object_id) FROM sys.views WHERE is_ms_shipped=0;
 INSERT #Metadata
 SELECT @scope,''PERMISSION'',CONCAT(p.name,''|'',dp.class_desc,''|'',dp.permission_name,''|'',
    COALESCE(OBJECT_SCHEMA_NAME(dp.major_id),''''),''.'',COALESCE(OBJECT_NAME(dp.major_id),''''),''|'',dp.minor_id),
    CONCAT(dp.state_desc,''|'',COALESCE(COL_NAME(dp.major_id,dp.minor_id),''''))
 FROM sys.database_permissions dp JOIN sys.database_principals p ON dp.grantee_principal_id=p.principal_id
 WHERE p.name IN (''dbrole_sales_clerk'',''dbrole_inventory_manager'',''dbrole_store_manager'');
 INSERT #Metadata
 SELECT @scope,''MEMBERSHIP'',r.name,m.name FROM sys.database_role_members rm
 JOIN sys.database_principals r ON rm.role_principal_id=r.principal_id
 JOIN sys.database_principals m ON rm.member_principal_id=m.principal_id
 WHERE r.name IN (''dbrole_sales_clerk'',''dbrole_inventory_manager'',''dbrole_store_manager'');';
EXEC sys.sp_executesql @MetadataSql,N'@scope varchar(8)',N'AFTER';
DECLARE @MetaRunner nvarchar(max)=N'EXEC '+@Ref+N'.sys.sp_executesql @s,N''@scope varchar(8)'',N''BEFORE'';';
EXEC sys.sp_executesql @MetaRunner,N'@s nvarchar(max)',@MetadataSql;
INSERT #Result
SELECT 'META_'+kind,N'除计划修改对象外结构与授权不变',CONCAT(N'差异数=',COUNT(*)),'FAIL'
FROM
 (SELECT * FROM
   (SELECT kind,object_name,value FROM #Metadata WHERE scope='BEFORE'
    EXCEPT SELECT kind,object_name,value FROM #Metadata WHERE scope='AFTER') b
  UNION ALL SELECT * FROM
   (SELECT kind,object_name,value FROM #Metadata WHERE scope='AFTER'
    EXCEPT SELECT kind,object_name,value FROM #Metadata WHERE scope='BEFORE') a) diff
GROUP BY kind;
INSERT #Result
SELECT DISTINCT 'META_'+kind,N'除计划修改对象外结构与授权不变',N'差异数=0','PASS'
FROM #Metadata m WHERE NOT EXISTS(SELECT 1 FROM #Result r WHERE r.test_id='META_'+m.kind);

INSERT #Result
SELECT 'TARGET_OBJECTS',N'活动唯一过滤索引及两项启用、受信任 CHECK 存在',
       CONCAT(N'对象数=',COUNT(*)),IIF(COUNT(*)=3,'PASS','FAIL')
FROM
 (SELECT name FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.PurchaseOrder')
    AND name=N'UX_PurchaseOrder_PresaleID' AND is_unique=1 AND has_filter=1 AND is_disabled=0
  UNION ALL SELECT name FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.PurchaseOrder')
    AND name IN (N'CK_PurchaseOrder_TypePresale',N'CK_PurchaseOrder_Status')
    AND is_disabled=0 AND is_not_trusted=0) x;

-- 下面的写入验证使用独立事务；全部回滚。夹具使用样例中已有的父记录。
DECLARE @Product int=(SELECT MIN(product_id) FROM dbo.Product),
        @Category int=(SELECT MIN(category_id) FROM dbo.ProductCategory),
        @Member int=(SELECT MIN(member_id) FROM dbo.Member),
        @Employee int=(SELECT MIN(employee_id) FROM dbo.Employee),
        @Supplier int=(SELECT MIN(supplier_id) FROM dbo.Supplier);
IF @Product IS NULL OR @Category IS NULL OR @Member IS NULL OR @Employee IS NULL OR @Supplier IS NULL
    THROW 51103,N'写入验证需要非空样例父表；空库不能算测试通过。',1;
IF EXISTS(SELECT 1 FROM dbo.PresaleActivity WHERE presale_id BETWEEN 986000 AND 986099)
 OR EXISTS(SELECT 1 FROM dbo.PurchaseOrder WHERE purchase_id BETWEEN 986000 AND 986099)
 OR EXISTS(SELECT 1 FROM dbo.SalesOrder WHERE order_id BETWEEN 986000 AND 986099)
 OR EXISTS(SELECT 1 FROM dbo.Product WHERE product_id BETWEEN 986000 AND 986099)
 OR EXISTS(SELECT 1 FROM dbo.ProductCategory WHERE category_id=2147483000)
    THROW 51104,N'测试编号与业务数据冲突，请换用干净的样例副本。',1;
IF DATABASE_PRINCIPAL_ID(N'u_test_sales') IS NULL
 OR DATABASE_PRINCIPAL_ID(N'u_test_inventory') IS NULL
 OR DATABASE_PRINCIPAL_ID(N'u_test_manager') IS NULL
    THROW 51105,N'缺少第一阶段 WITHOUT LOGIN 测试用户。',1;

DECLARE @Fixture nvarchar(max)=N'
 INSERT dbo.PresaleActivity(presale_id,presale_code,product_id,start_time,end_time,
 presale_unit_price,deposit_per_unit,created_by)
 VALUES(986001,''W6_PS1'',{P},''2026-01-01'',''2026-01-02'',50,10,{E}),
       (986002,''W6_PS2'',{P},''2026-01-01'',''2026-01-02'',50,10,{E});
 INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,presale_id,created_by,purchase_status)
 VALUES(986001,''W6_PO1'',{S},''PRESALE'',986001,{E},''CANCELLED''),
       (986002,''W6_PO2'',{S},''RESTOCK'',NULL,{E},''CREATED'');';
SET @Fixture=REPLACE(REPLACE(REPLACE(@Fixture,N'{P}',CAST(@Product AS nvarchar(20))),
 N'{E}',CAST(@Employee AS nvarchar(20))),N'{S}',CAST(@Supplier AS nvarchar(20)));
CREATE TABLE #Cases
 (id varchar(50) PRIMARY KEY,actor sysname NULL,sql_text nvarchar(max),error_number int NULL,error_object sysname NULL);
INSERT #Cases VALUES
 ('WRITE_RESTOCK',NULL,N'INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,created_by)
 VALUES(986010,''W6_RESTOCK'',{S},''RESTOCK'',{E}),(986011,''W6_RESTOCK2'',{S},''RESTOCK'',{E});',NULL,NULL),
 ('WRITE_PRESALE',NULL,N'INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,presale_id,created_by)
 VALUES(986010,''W6_PRESALE'',{S},''PRESALE'',986002,{E});',NULL,NULL),
 ('WRITE_ORDERED',NULL,N'UPDATE dbo.PurchaseOrder SET purchase_status=''ORDERED'' WHERE purchase_id=986002;',NULL,NULL),
 ('WRITE_RECEIVED',NULL,N'UPDATE dbo.PurchaseOrder SET purchase_status=''RECEIVED'',received_time=SYSDATETIME(),received_by={E}
 WHERE purchase_id=986002;',NULL,NULL),
 ('REJECT_DUP_ACTIVITY',NULL,N'INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,presale_id,created_by)
 VALUES(986010,''W6_DUP'',{S},''PRESALE'',986001,{E});',2601,N'UX_PurchaseOrder_PresaleID'),
 ('REJECT_RESTOCK_LINK',NULL,N'INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,presale_id,created_by)
 VALUES(986010,''W6_BAD_LINK'',{S},''RESTOCK'',986002,{E});',547,N'CK_PurchaseOrder_TypePresale'),
 ('REJECT_PRESALE_NULL',NULL,N'INSERT dbo.PurchaseOrder(purchase_id,purchase_no,supplier_id,purchase_type,created_by)
 VALUES(986010,''W6_NO_LINK'',{S},''PRESALE'',{E});',547,N'CK_PurchaseOrder_TypePresale'),
 ('REJECT_PARTIAL_STATUS',NULL,N'UPDATE dbo.PurchaseOrder SET purchase_status=''PARTIAL_RECEIVED'' WHERE purchase_id=986002;',547,N'CK_PurchaseOrder_Status'),
 ('REJECT_CATEGORY_FK',NULL,N'INSERT dbo.Product(product_id,product_code,product_name,category_id,sale_price)
 VALUES(986010,''W6_BAD_FK'',N''外码反例'',2147483000,10);',547,N'FK_Product_ProductCategory'),
 ('REJECT_QUANTITY',NULL,N'INSERT dbo.PurchaseOrderItem(purchase_id,product_id,ordered_qty,unit_cost)
 VALUES(986002,{P},0,10);',547,N'CK_PurchaseOrderItem_OrderedQty'),
 ('REJECT_PRODUCT_CODE',NULL,N'INSERT dbo.Product(product_id,product_code,product_name,category_id,sale_price)
 SELECT 986010,product_code,N''重复编号反例'',category_id,10 FROM dbo.Product WHERE product_id={P};',2627,N'UQ_Product_ProductCode'),
 ('ROLE_SALES_OK',N'u_test_sales',N'INSERT dbo.SalesOrder(order_id,order_no,order_type,member_id,cashier_id)
 VALUES(986010,''W6_SALE'',''SPOT'',{M},{E});
 INSERT dbo.SalesOrderItem(order_id,product_id,quantity,unit_price) VALUES(986010,{P},1,10);
 UPDATE dbo.SalesOrder SET order_status=''COMPLETED'',order_time=SYSDATETIME() WHERE order_id=986010;
 IF @@ROWCOUNT<>1 THROW 51110,N''销售更新行数不为1'',1;',NULL,NULL),
 ('ROLE_INVENTORY_OK',N'u_test_inventory',N'UPDATE dbo.Inventory SET reorder_point=reorder_point+1,updated_at=SYSDATETIME()
 WHERE product_id={P}; IF @@ROWCOUNT<>1 THROW 51111,N''库存更新行数不为1'',1;',NULL,NULL),
 ('ROLE_MANAGER_OK',N'u_test_manager',N'UPDATE dbo.Product SET sale_price=sale_price+1 WHERE product_id={P};
 IF @@ROWCOUNT<>1 THROW 51112,N''商品更新行数不为1'',1;',NULL,NULL),
 ('ROLE_SALES_DENY_PO',N'u_test_sales',N'UPDATE dbo.PurchaseOrder SET purchase_status=''CANCELLED'' WHERE purchase_id=986002;',229,N'PurchaseOrder'),
 ('ROLE_INVENTORY_DENY_MEMBER',N'u_test_inventory',N'SELECT * FROM dbo.Member;',229,N'Member'),
 ('ROLE_SALES_DENY_STOCK',N'u_test_sales',N'UPDATE dbo.Inventory SET on_hand_qty=on_hand_qty+1 WHERE product_id={P};',229,N'Inventory');

DECLARE @Actor sysname,@ExpectedError int,@ExpectedObject sysname,@Err int,@Message nvarchar(4000),
        @OuterUser sysname=USER_NAME();
DECLARE cases_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT id,actor,sql_text,error_number,error_object FROM #Cases ORDER BY id;
OPEN cases_cursor; FETCH NEXT FROM cases_cursor INTO @Name,@Actor,@Sql,@ExpectedError,@ExpectedObject;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @Sql=REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Sql,
      N'{P}',CAST(@Product AS nvarchar(20))),N'{E}',CAST(@Employee AS nvarchar(20))),
      N'{S}',CAST(@Supplier AS nvarchar(20))),N'{M}',CAST(@Member AS nvarchar(20))),
      N'{C}',CAST(@Category AS nvarchar(20)));
    BEGIN TRY
        BEGIN TRAN;
        EXEC sys.sp_executesql @Fixture;
        IF @Actor IS NOT NULL EXECUTE AS USER=@Actor;
        EXEC sys.sp_executesql @Sql;
        IF @Actor IS NOT NULL REVERT;
        ROLLBACK;
        INSERT #Result VALUES(@Name,IIF(@ExpectedError IS NULL,N'合法操作成功',CONCAT(N'错误 ',@ExpectedError,N' / ',@ExpectedObject)),
          N'操作成功，测试事务已回滚',IIF(@ExpectedError IS NULL,'PASS','FAIL'));
    END TRY
    BEGIN CATCH
        SELECT @Err=ERROR_NUMBER(),@Message=ERROR_MESSAGE();
        IF USER_NAME()<>@OuterUser REVERT;
        IF XACT_STATE()<>0 ROLLBACK;
        INSERT #Result VALUES(@Name,IIF(@ExpectedError IS NULL,N'合法操作成功',CONCAT(N'错误 ',@ExpectedError,N' / ',@ExpectedObject)),
          CONCAT(N'错误 ',@Err,N'；',@Message),
          IIF(@Err=@ExpectedError AND CHARINDEX(@ExpectedObject,@Message)>0,'PASS','FAIL'));
    END CATCH;
    FETCH NEXT FROM cases_cursor INTO @Name,@Actor,@Sql,@ExpectedError,@ExpectedObject;
END;
CLOSE cases_cursor; DEALLOCATE cases_cursor;

SELECT * FROM #Result ORDER BY test_id;
SELECT DB_NAME() AS target_database,@BaselineDatabase AS baseline_database,
       SUM(IIF(status='PASS',1,0)) AS passed,SUM(IIF(status='FAIL',1,0)) AS failed FROM #Result;
-- 展示三类关键结果，便于保存实际业务值，而非只保存 PASS。
SELECT N'订单金额' AS result_kind,so.order_no,COUNT(i.product_id) AS item_count,
       COALESCE(SUM(i.quantity*i.unit_price),0) AS amount
FROM dbo.SalesOrder so LEFT JOIN dbo.SalesOrderItem i ON i.order_id=so.order_id GROUP BY so.order_no ORDER BY so.order_no;
SELECT * FROM dbo.vw_ProductSalesSummary ORDER BY product_id;
SELECT * FROM dbo.vw_InventoryStatus ORDER BY product_id;
IF EXISTS(SELECT 1 FROM #Result WHERE status='FAIL')
    THROW 51199,N'第六周回归存在 FAIL，请检查结果表。',1;
