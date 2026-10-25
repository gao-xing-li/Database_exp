/* =========================================================
   03_crud.sql

   CRUD 演示：
   1. 商品
   2. 库存
   3. 销售订单及订单明细

   执行前：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   第一部分：商品与库存 CRUD
   ========================================================= */


/* ---------------------------------------------------------
   C = CREATE / INSERT

   新增一个测试商品
   --------------------------------------------------------- */

INSERT INTO dbo.Product
(
    product_id,
    product_code,
    product_name,
    category_id,
    ip_id,
    character_id,
    sale_price,
    product_status
)
VALUES
(
    9001,
    'P_TEST',
    N'CRUD测试商品',
    1,
    NULL,
    NULL,
    20.00,
    'ON_SALE'
);
GO


/* 为新商品建立库存记录 */

INSERT INTO dbo.Inventory
(
    product_id,
    on_hand_qty,
    reserved_qty,
    reorder_point
)
VALUES
(
    9001,
    10,
    0,
    3
);
GO


/* ---------------------------------------------------------
   R = READ / SELECT
   --------------------------------------------------------- */

SELECT
    p.product_id,
    p.product_code,
    p.product_name,
    p.sale_price,
    p.product_status,
    i.on_hand_qty,
    i.reserved_qty,
    i.on_hand_qty - i.reserved_qty AS available_qty,
    i.reorder_point
FROM dbo.Product AS p
JOIN dbo.Inventory AS i
    ON p.product_id = i.product_id
WHERE p.product_id = 9001;
GO


/* ---------------------------------------------------------
   U = UPDATE

   修改前先使用相同 WHERE 条件进行 SELECT。
   --------------------------------------------------------- */

SELECT *
FROM dbo.Product
WHERE product_id = 9001;
GO


UPDATE dbo.Product
SET
    sale_price = 22.00,
    product_name = N'CRUD测试商品（修改后）'
WHERE product_id = 9001;
GO


SELECT *
FROM dbo.Product
WHERE product_id = 9001;
GO


/* 库存更新 */

SELECT *
FROM dbo.Inventory
WHERE product_id = 9001;
GO


UPDATE dbo.Inventory
SET
    on_hand_qty = 15,
    reorder_point = 5,
    updated_at = SYSDATETIME()
WHERE product_id = 9001;
GO


SELECT
    *,
    on_hand_qty - reserved_qty AS available_qty
FROM dbo.Inventory
WHERE product_id = 9001;
GO


/* ---------------------------------------------------------
   D = DELETE

   Product 被 Inventory 引用，因此不能直接先删 Product。
   先确认待删除数据。
   --------------------------------------------------------- */

SELECT *
FROM dbo.Inventory
WHERE product_id = 9001;

SELECT *
FROM dbo.Product
WHERE product_id = 9001;
GO


/* 先删除子表 */

DELETE FROM dbo.Inventory
WHERE product_id = 9001;
GO


/* 再删除父表 */

DELETE FROM dbo.Product
WHERE product_id = 9001;
GO


/* 确认已经删除 */

SELECT *
FROM dbo.Product
WHERE product_id = 9001;

SELECT *
FROM dbo.Inventory
WHERE product_id = 9001;
GO



/* =========================================================
   第二部分：销售订单 CRUD
   ========================================================= */


/* ---------------------------------------------------------
   C = CREATE

   创建一笔普通现货测试订单。
   --------------------------------------------------------- */

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
    9001,
    'SO_TEST',
    'SPOT',
    NULL,
    1,
    NULL,
    NULL,
    'CREATED'
);
GO


/* 添加订单明细 */

INSERT INTO dbo.SalesOrderItem
(
    order_id,
    product_id,
    quantity,
    unit_price
)
VALUES
(
    9001,
    1,
    1,
    68.00
);
GO


/* ---------------------------------------------------------
   R = READ

   联表查询这笔测试订单。
   --------------------------------------------------------- */

SELECT
    so.order_id,
    so.order_no,
    so.order_type,
    so.order_status,
    p.product_name,
    soi.quantity,
    soi.unit_price,
    soi.quantity * soi.unit_price AS item_amount
FROM dbo.SalesOrder AS so
JOIN dbo.SalesOrderItem AS soi
    ON so.order_id = soi.order_id
JOIN dbo.Product AS p
    ON soi.product_id = p.product_id
WHERE so.order_id = 9001;
GO


/* ---------------------------------------------------------
   U = UPDATE

   在订单完成前先修改并确认订单明细。
   --------------------------------------------------------- */

SELECT *
FROM dbo.SalesOrderItem
WHERE order_id = 9001
  AND product_id = 1;
GO


UPDATE dbo.SalesOrderItem
SET quantity = 2
WHERE order_id = 9001
  AND product_id = 1;
GO


SELECT
    order_id,
    product_id,
    quantity,
    unit_price,
    quantity * unit_price AS item_amount
FROM dbo.SalesOrderItem
WHERE order_id = 9001
  AND product_id = 1;
GO


/* 确认明细后，将订单由 CREATED 变为 COMPLETED */

SELECT *
FROM dbo.SalesOrder
WHERE order_id = 9001;
GO


UPDATE dbo.SalesOrder
SET
    order_status = 'COMPLETED',
    order_time = SYSDATETIME()
WHERE order_id = 9001;
GO


SELECT *
FROM dbo.SalesOrder
WHERE order_id = 9001;
GO


/* ---------------------------------------------------------
   D = DELETE

   SalesOrderItem 引用了 SalesOrder，
   所以仍然按照子表 → 父表顺序删除。
   --------------------------------------------------------- */

SELECT *
FROM dbo.SalesOrderItem
WHERE order_id = 9001;

SELECT *
FROM dbo.SalesOrder
WHERE order_id = 9001;
GO


DELETE FROM dbo.SalesOrderItem
WHERE order_id = 9001;
GO


DELETE FROM dbo.SalesOrder
WHERE order_id = 9001;
GO


/* 最终验证 */

SELECT *
FROM dbo.SalesOrder
WHERE order_id = 9001;

SELECT *
FROM dbo.SalesOrderItem
WHERE order_id = 9001;
GO