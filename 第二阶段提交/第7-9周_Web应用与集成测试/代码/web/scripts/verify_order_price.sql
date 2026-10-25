-- 只读核对登记单价与结账结果，将下方订单号替换为本次刚完成的订单。
USE AnimeGoodsStoreDB_Week6App;
GO
DECLARE @OrderNo varchar(30) = '请填入此次订单编号';
SELECT o.order_no AS 订单编号, o.order_status AS 订单状态,
       p.product_code AS 商品编号, p.sale_price AS 当前目录标价,
       i.unit_price AS 本单登记单价, i.quantity AS 数量,
       i.quantity * i.unit_price AS 明细金额
FROM dbo.SalesOrder AS o
JOIN dbo.SalesOrderItem AS i ON i.order_id = o.order_id
JOIN dbo.Product AS p ON p.product_id = i.product_id
WHERE o.order_no = @OrderNo
ORDER BY p.product_id;
