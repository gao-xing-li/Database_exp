/* =========================================================
   02_insert_sample_data.sql
   二次元周边商品店：插入样例数据

   执行顺序：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql

   说明：
   本脚本假设当前数据库中的业务表为空。
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   1. 商品类别 ProductCategory
   ========================================================= */

INSERT INTO dbo.ProductCategory
    (category_id, category_name, description)
VALUES
    (1, N'徽章',       N'马口铁徽章、吧唧等商品'),
    (2, N'亚克力制品', N'亚克力立牌、挂件等商品'),
    (3, N'玩偶',       N'毛绒玩偶等商品'),
    (4, N'色纸',       N'色纸、纸制收藏品等商品');
GO


/* =========================================================
   2. 作品 / IP AnimeIP
   ========================================================= */

INSERT INTO dbo.AnimeIP
    (ip_id, ip_name, description)
VALUES
    (1, N'原神',           N'游戏相关IP'),
    (2, N'崩坏：星穹铁道', N'游戏相关IP'),
    (3, N'初音未来',       N'虚拟歌手相关IP');
GO


/* =========================================================
   3. 员工业务角色 BusinessRole
   ========================================================= */

INSERT INTO dbo.BusinessRole
    (role_id, role_name, description)
VALUES
    (1, N'销售/收银店员', N'销售结账、订单处理和会员信息处理'),
    (2, N'库存管理员',    N'到货验收、入库、盘点和库存检查'),
    (3, N'店长/管理员',   N'商品、员工、供应商及采购决策管理');
GO


/* =========================================================
   4. 会员 Member
   ========================================================= */

INSERT INTO dbo.Member
    (
        member_id,
        member_no,
        member_name,
        phone,
        register_time,
        member_status
    )
VALUES
    (1, 'M001', N'林晓', '13800000001',
     '2026-08-20T10:00:00', 'ACTIVE'),

    (2, 'M002', N'陈雨', '13800000002',
     '2026-09-01T15:30:00', 'ACTIVE'),

    (3, 'M003', N'周琪', '13800000003',
     '2026-09-10T11:20:00', 'ACTIVE'),

    -- 以下为第三周扩充测试数据
    (4, 'M004', N'许安', '13800000004',
     '2026-09-15T17:10:00', 'ACTIVE'),

    (5, 'M005', N'顾宁', '13800000005',
     '2026-09-18T09:40:00', 'ACTIVE');
GO


/* =========================================================
   5. 供应商 Supplier
   ========================================================= */

INSERT INTO dbo.Supplier
    (
        supplier_id,
        supplier_code,
        supplier_name,
        contact_name,
        phone,
        supplier_status
    )
VALUES
    (1, 'S001', N'星海周边供应社',
     N'张明', '13700000001', 'ACTIVE'),

    (2, 'S002', N'次元商品供应中心',
     N'刘悦', '13700000002', 'ACTIVE'),

    (3, 'S003', N'海蓝文创供应商',
     N'陈华', '13700000003', 'ACTIVE');
GO


/* =========================================================
   6. 角色 CharacterInfo
   ========================================================= */

INSERT INTO dbo.CharacterInfo
    (character_id, ip_id, character_name)
VALUES
    (1, 1, N'甘雨'),
    (2, 1, N'派蒙'),
    (3, 2, N'三月七'),

    -- 第三周扩充，用于增加商品样例
    (4, 3, N'初音未来');
GO


/* =========================================================
   7. 员工 Employee
   ========================================================= */

INSERT INTO dbo.Employee
    (
        employee_id,
        employee_no,
        employee_name,
        role_id,
        phone,
        hire_date,
        employee_status
    )
VALUES
    (1, 'E001', N'李晨', 1,
     '13900000001', '2026-07-01', 'ACTIVE'),

    (2, 'E002', N'周宁', 2,
     '13900000002', '2026-07-01', 'ACTIVE'),

    (3, 'E003', N'王敏', 3,
     '13900000003', '2026-06-15', 'ACTIVE');
GO


/* =========================================================
   8. 商品 Product

   P001～P003 为第二周原样例。
   P004～P006 用于扩充后续查询数据。
   ========================================================= */

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
    (1, 'P001', N'甘雨亚克力立牌',
     2, 1, 1, 68.00, 'ON_SALE'),

    (2, 'P002', N'原神群像徽章套装',
     1, 1, NULL, 45.00, 'ON_SALE'),

    (3, 'P003', N'三月七毛绒玩偶',
     3, 2, 3, 129.00, 'ON_SALE'),

    (4, 'P004', N'派蒙徽章',
     1, 1, 2, 28.00, 'ON_SALE'),

    (5, 'P005', N'星穹铁道群像色纸',
     4, 2, NULL, 35.00, 'ON_SALE'),

    (6, 'P006', N'初音未来亚克力挂件',
     2, 3, 4, 39.00, 'ON_SALE');
GO


/* =========================================================
   9. 当前库存 Inventory

   available_qty 不保存：
   available_qty = on_hand_qty - reserved_qty
   ========================================================= */

INSERT INTO dbo.Inventory
    (
        product_id,
        on_hand_qty,
        reserved_qty,
        reorder_point
    )
VALUES
    (1,  8, 0, 5),
    (2,  5, 0, 4),
    (3,  2, 0, 3),

    (4, 12, 0, 5),
    (5,  6, 0, 3),
    (6,  9, 0, 4);
GO


/* =========================================================
   10. 预售活动 PresaleActivity

   PS001：
   已结束的预售案例。

   PS002：
   当前仍开放的预售案例。
   ========================================================= */

INSERT INTO dbo.PresaleActivity
    (
        presale_id,
        presale_code,
        product_id,
        start_time,
        end_time,
        presale_unit_price,
        deposit_per_unit,
        pickup_deadline,
        decision_demand_qty,
        extra_stock_qty,
        planned_purchase_qty,
        created_by,
        presale_status
    )
VALUES
    (
        1,
        'PS001',
        3,
        '2026-09-01T00:00:00',
        '2026-09-15T23:59:59',
        129.00,
        30.00,
        '2026-10-10T23:59:59',
        2,
        1,
        3,
        3,
        'FINISHED'
    ),

    (
        2,
        'PS002',
        1,
        '2026-09-20T00:00:00',
        '2026-10-05T23:59:59',
        68.00,
        20.00,
        NULL,
        NULL,
        0,
        NULL,
        3,
        'OPEN'
    );
GO


/* =========================================================
   11. 预售预订 PresaleReservation
   ========================================================= */

INSERT INTO dbo.PresaleReservation
    (
        reservation_id,
        reservation_no,
        presale_id,
        member_id,
        quantity,
        reserved_at,
        deposit_paid,
        deposit_refunded,
        reservation_status,
        cancelled_at
    )
VALUES
    -- 已正常提货
    (
        1, 'R001',
        1, 1,
        1,
        '2026-09-05T10:00:00',
        30.00,
        0.00,
        'PICKED_UP',
        NULL
    ),

    -- PS001 在 9 月 15 日截止，
    -- 该会员在 9 月 18 日取消，因此订金不退
    (
        2, 'R002',
        1, 2,
        1,
        '2026-09-06T15:00:00',
        30.00,
        0.00,
        'CANCELLED',
        '2026-09-18T11:00:00'
    ),

    -- 当前开放中的预售
    (
        3, 'R003',
        2, 2,
        1,
        '2026-09-22T14:00:00',
        20.00,
        0.00,
        'ACTIVE',
        NULL
    ),

    -- 第三周扩充测试数据
    (
        4, 'R004',
        2, 3,
        2,
        '2026-09-24T16:30:00',
        40.00,
        0.00,
        'ACTIVE',
        NULL
    );
GO


/* =========================================================
   12. 采购订单 PurchaseOrder
   ========================================================= */

INSERT INTO dbo.PurchaseOrder
    (
        purchase_id,
        purchase_no,
        supplier_id,
        purchase_type,
        presale_id,
        created_by,
        order_time,
        expected_arrival,
        received_time,
        received_by,
        purchase_status
    )
VALUES
    -- PS001 对应的预售采购
    (
        1, 'PO001',
        1,
        'PRESALE',
        1,
        3,
        '2026-09-16T10:00:00',
        '2026-09-25T10:00:00',
        '2026-09-25T14:00:00',
        2,
        'RECEIVED'
    ),

    -- 尚未到货的普通补货
    (
        2, 'PO002',
        2,
        'RESTOCK',
        NULL,
        3,
        '2026-09-20T09:00:00',
        '2026-09-30T10:00:00',
        NULL,
        NULL,
        'ORDERED'
    ),

    -- 已完成的普通补货，作为额外测试数据
    (
        3, 'PO003',
        3,
        'RESTOCK',
        NULL,
        3,
        '2026-09-10T09:00:00',
        '2026-09-14T10:00:00',
        '2026-09-14T16:00:00',
        2,
        'RECEIVED'
    );
GO


/* =========================================================
   13. 采购订单明细 PurchaseOrderItem
   ========================================================= */

INSERT INTO dbo.PurchaseOrderItem
    (
        purchase_id,
        product_id,
        ordered_qty,
        unit_cost,
        received_qty
    )
VALUES
    -- PO001：预售采购
    (1, 3,  3, 85.00, 3),

    -- PO002：普通补货，尚未到货
    (2, 1, 10, 40.00, 0),
    (2, 2, 20, 22.00, 0),

    -- PO003：已到货普通补货
    (3, 4, 15, 15.00, 15),
    (3, 6, 10, 23.00, 10);
GO


/* =========================================================
   14. 销售订单 SalesOrder
   ========================================================= */

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
    -- 普通非会员购买
    (
        1, 'SO001',
        'SPOT',
        NULL,
        1,
        NULL,
        '2026-09-22T14:30:00',
        'COMPLETED'
    ),

    -- 普通会员购买
    (
        2, 'SO002',
        'SPOT',
        2,
        1,
        NULL,
        '2026-09-23T16:10:00',
        'COMPLETED'
    ),

    -- R001 的预售提货订单
    (
        3, 'SO003',
        'PRESALE',
        1,
        1,
        1,
        '2026-09-26T10:20:00',
        'COMPLETED'
    ),

    -- 后续为统计查询扩充的数据
    (
        4, 'SO004',
        'SPOT',
        1,
        1,
        NULL,
        '2026-09-24T13:10:00',
        'COMPLETED'
    ),

    (
        5, 'SO005',
        'SPOT',
        3,
        1,
        NULL,
        '2026-09-25T17:40:00',
        'COMPLETED'
    ),

    (
        6, 'SO006',
        'SPOT',
        NULL,
        1,
        NULL,
        '2026-09-26T09:20:00',
        'COMPLETED'
    );
GO


/* =========================================================
   15. 销售订单明细 SalesOrderItem

   普通现货订单允许包含多种商品；当前预售提货按一次预订独立结账。
   unit_price 保存历史实际成交价格。
   ========================================================= */

INSERT INTO dbo.SalesOrderItem
    (
        order_id,
        product_id,
        quantity,
        unit_price
    )
VALUES
    -- 第二周原有样例
    (1, 1, 1,  68.00),

    (2, 2, 2,  45.00),

    (3, 3, 1, 129.00),

    -- SO004：一张订单购买两种商品
    (4, 1, 1, 68.00),
    (4, 4, 2, 28.00),

    -- SO005：另一张多商品订单
    (5, 5, 1, 35.00),
    (5, 6, 1, 39.00),

    (6, 2, 1, 45.00);
GO


/* =========================================================
   样例数据基本检查
   ========================================================= */

SELECT 'ProductCategory' AS table_name, COUNT(*) AS row_count
FROM dbo.ProductCategory

UNION ALL
SELECT 'AnimeIP', COUNT(*) FROM dbo.AnimeIP

UNION ALL
SELECT 'CharacterInfo', COUNT(*) FROM dbo.CharacterInfo

UNION ALL
SELECT 'Product', COUNT(*) FROM dbo.Product

UNION ALL
SELECT 'Inventory', COUNT(*) FROM dbo.Inventory

UNION ALL
SELECT 'Member', COUNT(*) FROM dbo.Member

UNION ALL
SELECT 'BusinessRole', COUNT(*) FROM dbo.BusinessRole

UNION ALL
SELECT 'Employee', COUNT(*) FROM dbo.Employee

UNION ALL
SELECT 'Supplier', COUNT(*) FROM dbo.Supplier

UNION ALL
SELECT 'PresaleActivity', COUNT(*) FROM dbo.PresaleActivity

UNION ALL
SELECT 'PresaleReservation', COUNT(*) FROM dbo.PresaleReservation

UNION ALL
SELECT 'PurchaseOrder', COUNT(*) FROM dbo.PurchaseOrder

UNION ALL
SELECT 'PurchaseOrderItem', COUNT(*) FROM dbo.PurchaseOrderItem

UNION ALL
SELECT 'SalesOrder', COUNT(*) FROM dbo.SalesOrder

UNION ALL
SELECT 'SalesOrderItem', COUNT(*) FROM dbo.SalesOrderItem;
GO