/* =========================================================
   05_view.sql
   二次元周边商品店：第四周统计视图

   执行前：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   V1. 订单详情视图
   ========================================================= */

CREATE VIEW dbo.vw_OrderDetail
AS
SELECT
    so.order_id,
    so.order_no,
    so.order_type,
    so.order_status,
    so.order_time,

    so.member_id,
    m.member_no,
    m.member_name,

    so.cashier_id,
    e.employee_no AS cashier_no,
    e.employee_name AS cashier_name,

    soi.product_id,
    p.product_code,
    p.product_name,

    soi.quantity,
    soi.unit_price,
    soi.quantity * soi.unit_price AS item_amount

FROM dbo.SalesOrder AS so
INNER JOIN dbo.SalesOrderItem AS soi
    ON so.order_id = soi.order_id
INNER JOIN dbo.Product AS p
    ON soi.product_id = p.product_id
INNER JOIN dbo.Employee AS e
    ON so.cashier_id = e.employee_id
LEFT JOIN dbo.Member AS m
    ON so.member_id = m.member_id;
GO


/* 验证订单详情视图 */

SELECT *
FROM dbo.vw_OrderDetail
ORDER BY order_id, product_id;
GO



/* =========================================================
   V2. 商品销售统计视图

   仅 COMPLETED 订单计入实际销量和销售额。
   没有产生销量的商品仍保留，统计值为 0。
   ========================================================= */

CREATE VIEW dbo.vw_ProductSalesSummary
AS
SELECT
    p.product_id,
    p.product_code,
    p.product_name,

    SUM(
        CASE
            WHEN so.order_status = 'COMPLETED'
            THEN soi.quantity
            ELSE 0
        END
    ) AS total_sales_qty,

    SUM(
        CASE
            WHEN so.order_status = 'COMPLETED'
            THEN soi.quantity * soi.unit_price
            ELSE 0
        END
    ) AS total_sales_amount

FROM dbo.Product AS p
LEFT JOIN dbo.SalesOrderItem AS soi
    ON p.product_id = soi.product_id
LEFT JOIN dbo.SalesOrder AS so
    ON soi.order_id = so.order_id

GROUP BY
    p.product_id,
    p.product_code,
    p.product_name;
GO


/* 验证商品销售统计视图 */

SELECT *
FROM dbo.vw_ProductSalesSummary
ORDER BY total_sales_qty DESC, product_id;
GO



/* =========================================================
   V3. 库存状态视图

   available_qty = on_hand_qty - reserved_qty

   OUT_OF_STOCK：可销售库存为 0
   LOW_STOCK：可销售库存达到或低于补货警戒值
   NORMAL：库存正常
   ========================================================= */

CREATE VIEW dbo.vw_InventoryStatus
AS
SELECT
    p.product_id,
    p.product_code,
    p.product_name,

    i.on_hand_qty,
    i.reserved_qty,

    i.on_hand_qty - i.reserved_qty AS available_qty,

    i.reorder_point,

    CASE
        WHEN i.on_hand_qty - i.reserved_qty = 0
            THEN 'OUT_OF_STOCK'

        WHEN i.on_hand_qty - i.reserved_qty <= i.reorder_point
            THEN 'LOW_STOCK'

        ELSE 'NORMAL'
    END AS stock_status,

    i.updated_at

FROM dbo.Product AS p
INNER JOIN dbo.Inventory AS i
    ON p.product_id = i.product_id;
GO


/* 验证库存状态视图 */

SELECT *
FROM dbo.vw_InventoryStatus
ORDER BY available_qty, product_id;
GO



/* =========================================================
   V4. 会员消费统计视图

   即使会员当前没有产生消费，也保留该会员，
   completed_order_count 和 total_consumption 为 0。
   ========================================================= */

CREATE VIEW dbo.vw_MemberConsumptionSummary
AS
SELECT
    m.member_id,
    m.member_no,
    m.member_name,

    COUNT(DISTINCT so.order_id)
        AS completed_order_count,

    COALESCE(
        SUM(soi.quantity * soi.unit_price),
        0
    ) AS total_consumption

FROM dbo.Member AS m

LEFT JOIN dbo.SalesOrder AS so
    ON m.member_id = so.member_id
   AND so.order_status = 'COMPLETED'

LEFT JOIN dbo.SalesOrderItem AS soi
    ON so.order_id = soi.order_id

GROUP BY
    m.member_id,
    m.member_no,
    m.member_name;
GO


/* 验证会员消费统计视图 */

SELECT *
FROM dbo.vw_MemberConsumptionSummary
ORDER BY total_consumption DESC, member_id;
GO