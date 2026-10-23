/* 第五周：复用已有视图，展示任务指定的三个 ER 案例。
   前提：已有第一阶段表、样例及 05_view.sql 中的视图。
   在 SSMS 执行；不创建对象、不写数据。空结果需先确认实例和样例。
*/
USE AnimeGoodsStoreDB;
GO

-- 1. R09、R10：订单—明细—商品。
-- SO004：P001 一件 × 68、P004 两件 × 28；两条明细，合计 124。
SELECT order_no, product_code, product_name, quantity, unit_price, item_amount
FROM dbo.vw_OrderDetail
WHERE order_no = 'SO004'
ORDER BY product_id;

-- 2. R07：会员可选参与订单。
-- SO001 会员为空；SO002 对应 M002。DISTINCT 去除明细造成的重复。
SELECT DISTINCT order_no, member_no, member_name
FROM dbo.vw_OrderDetail
WHERE order_no IN ('SO001', 'SO002')
ORDER BY order_no;

-- 3. R05、B01：商品—库存；可售量 = 在库 - 预留。
-- P003：在库 2、预留 0、可售 2、警戒值 3，LOW_STOCK。
-- 原视图用 INNER JOIN，无库存记录的商品不显示，该边界在问题清单说明。
SELECT product_code, product_name, on_hand_qty, reserved_qty,
       available_qty, reorder_point, stock_status
FROM dbo.vw_InventoryStatus
WHERE product_code = 'P003';
