/* =========================================================
   04_query.sql
   二次元周边商品店：第四周业务查询

   执行前：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   Q1. 查看完整销售订单明细

   业务问题：
   查看每笔订单由谁结账、会员是谁、购买了什么商品、
   数量、成交单价及明细金额。

   使用 LEFT JOIN Member：
   因为普通非会员顾客的 member_id 可以为 NULL。
   ========================================================= */

SELECT
    so.order_no,
    so.order_type,
    so.order_status,
    so.order_time,

    m.member_no,
    m.member_name,

    e.employee_no AS cashier_no,
    e.employee_name AS cashier_name,

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
    ON so.member_id = m.member_id
ORDER BY so.order_id, p.product_id;
GO


/* =========================================================
   Q2. 统计每种商品的累计销量和销售额

   只把 COMPLETED 订单计入实际销量。

   从 Product 出发并使用 LEFT JOIN，
   使尚未产生销售记录的商品仍然可以显示为 0。
   ========================================================= */

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
    p.product_name
ORDER BY total_sales_qty DESC, p.product_id;
GO


/* =========================================================
   Q3. 按 IP 统计累计销量和销售额

   用于分析不同作品 / IP 的销售表现。
   ========================================================= */

SELECT
    ip.ip_id,
    ip.ip_name,

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

FROM dbo.AnimeIP AS ip
LEFT JOIN dbo.Product AS p
    ON ip.ip_id = p.ip_id
LEFT JOIN dbo.SalesOrderItem AS soi
    ON p.product_id = soi.product_id
LEFT JOIN dbo.SalesOrder AS so
    ON soi.order_id = so.order_id
GROUP BY
    ip.ip_id,
    ip.ip_name
ORDER BY total_sales_amount DESC;
GO


/* =========================================================
   Q4. 按商品类别统计累计销量和销售额

   与 IP 统计角度不同：
   这里分析徽章、亚克力制品、玩偶、色纸等商品类别。
   ========================================================= */

SELECT
    pc.category_id,
    pc.category_name,

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

FROM dbo.ProductCategory AS pc
LEFT JOIN dbo.Product AS p
    ON pc.category_id = p.category_id
LEFT JOIN dbo.SalesOrderItem AS soi
    ON p.product_id = soi.product_id
LEFT JOIN dbo.SalesOrder AS so
    ON soi.order_id = so.order_id
GROUP BY
    pc.category_id,
    pc.category_name
ORDER BY total_sales_amount DESC;
GO


/* =========================================================
   Q5. 统计每个会员的消费次数和累计消费金额

   要求：
   即使会员尚未产生任何消费，也要显示出来。

   COUNT(DISTINCT so.order_id)：
   避免一张包含多个商品的订单被重复计算为多笔订单。
   ========================================================= */

SELECT
    m.member_id,
    m.member_no,
    m.member_name,

    COUNT(DISTINCT so.order_id) AS completed_order_count,

    SUM(
        COALESCE(soi.quantity * soi.unit_price, 0)
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
    m.member_name
ORDER BY total_consumption DESC;
GO


/* =========================================================
   Q6. 查询当前达到或低于补货警戒值的商品

   可销售库存：
   available_qty = on_hand_qty - reserved_qty
   ========================================================= */

SELECT
    p.product_id,
    p.product_code,
    p.product_name,

    i.on_hand_qty,
    i.reserved_qty,
    i.on_hand_qty - i.reserved_qty AS available_qty,
    i.reorder_point

FROM dbo.Product AS p
INNER JOIN dbo.Inventory AS i
    ON p.product_id = i.product_id

WHERE
    i.on_hand_qty - i.reserved_qty <= i.reorder_point

ORDER BY
    available_qty ASC,
    p.product_id;
GO


/* =========================================================
   Q7. 统计各预售活动当前有效预订需求

   ACTIVE 表示当前仍然有效、尚未取消、
   尚未完成提货的预订。

   同时显示 decision_demand_qty，
   用于与采购决策时保存的历史需求快照比较。
   ========================================================= */

SELECT
    pa.presale_id,
    pa.presale_code,
    p.product_code,
    p.product_name,
    pa.presale_status,

    SUM(
        CASE
            WHEN pr.reservation_status = 'ACTIVE'
            THEN pr.quantity
            ELSE 0
        END
    ) AS current_active_demand_qty,

    pa.decision_demand_qty,
    pa.extra_stock_qty,
    pa.planned_purchase_qty

FROM dbo.PresaleActivity AS pa
INNER JOIN dbo.Product AS p
    ON pa.product_id = p.product_id
LEFT JOIN dbo.PresaleReservation AS pr
    ON pa.presale_id = pr.presale_id
GROUP BY
    pa.presale_id,
    pa.presale_code,
    p.product_code,
    p.product_name,
    pa.presale_status,
    pa.decision_demand_qty,
    pa.extra_stock_qty,
    pa.planned_purchase_qty
ORDER BY pa.presale_id;
GO


/* =========================================================
   Q8. 查询累计销量不少于 2 件的商品

   使用 HAVING：
   因为筛选条件作用于 SUM(quantity) 聚合结果，
   而不是某一条原始记录。
   ========================================================= */

SELECT
    p.product_id,
    p.product_code,
    p.product_name,
    SUM(soi.quantity) AS total_sales_qty,
    SUM(soi.quantity * soi.unit_price) AS total_sales_amount

FROM dbo.Product AS p
INNER JOIN dbo.SalesOrderItem AS soi
    ON p.product_id = soi.product_id
INNER JOIN dbo.SalesOrder AS so
    ON soi.order_id = so.order_id

WHERE so.order_status = 'COMPLETED'

GROUP BY
    p.product_id,
    p.product_code,
    p.product_name

HAVING SUM(soi.quantity) >= 2

ORDER BY total_sales_qty DESC;
GO


/* =========================================================
   Q9. 查询累计消费金额高于会员平均消费金额的会员

   第一步：
   计算每个有实际消费记录会员的累计消费金额。

   第二步：
   对这些会员的累计消费额求平均值。

   第三步：
   找出高于该平均值的会员。
   ========================================================= */

SELECT
    mc.member_id,
    mc.member_no,
    mc.member_name,
    mc.total_consumption

FROM
(
    SELECT
        m.member_id,
        m.member_no,
        m.member_name,
        SUM(soi.quantity * soi.unit_price) AS total_consumption

    FROM dbo.Member AS m
    INNER JOIN dbo.SalesOrder AS so
        ON m.member_id = so.member_id
    INNER JOIN dbo.SalesOrderItem AS soi
        ON so.order_id = soi.order_id

    WHERE so.order_status = 'COMPLETED'

    GROUP BY
        m.member_id,
        m.member_no,
        m.member_name
) AS mc

WHERE mc.total_consumption >
(
    SELECT AVG(CAST(member_total.total_consumption AS DECIMAL(18,2)))
    FROM
    (
        SELECT
            so2.member_id,
            SUM(
                soi2.quantity * soi2.unit_price
            ) AS total_consumption

        FROM dbo.SalesOrder AS so2
        INNER JOIN dbo.SalesOrderItem AS soi2
            ON so2.order_id = soi2.order_id

        WHERE
            so2.order_status = 'COMPLETED'
            AND so2.member_id IS NOT NULL

        GROUP BY so2.member_id
    ) AS member_total
)

ORDER BY mc.total_consumption DESC;
GO