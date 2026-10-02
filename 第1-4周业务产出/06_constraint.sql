/* =========================================================
   06_constraint.sql
   二次元周边商品店：完整性约束补充与验证

   执行前：
   00_create_database.sql
   01_create_tables.sql
   02_insert_sample_data.sql

   本文件完成：
   1. 补充必要的完整性约束
   2. 合法数据正例测试
   3. T1-T14 非法数据反例测试（仅因预期约束失败才判定 PASS）

   所有测试均使用事务并回滚，不修改正式样例数据。
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   第一部分：补充完整性约束
   ========================================================= */


/* ---------------------------------------------------------
   PresaleReservation：
   已退订金不能超过实际支付订金。

   原有约束已经分别保证：
       deposit_paid >= 0
       deposit_refunded >= 0

   这里进一步补充二者之间的关系：
       deposit_refunded <= deposit_paid
   --------------------------------------------------------- */

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = N'CK_PresaleReservation_RefundNotExceedPaid'
      AND parent_object_id = OBJECT_ID(N'dbo.PresaleReservation')
)
BEGIN
    ALTER TABLE dbo.PresaleReservation
    WITH CHECK
    ADD CONSTRAINT CK_PresaleReservation_RefundNotExceedPaid
        CHECK (deposit_refunded <= deposit_paid);
END;
GO



/* =========================================================
   第二部分：合法数据正例
   ========================================================= */


/* ---------------------------------------------------------
   正例 P1：
   合法商品 + 合法库存能够正常插入。

   测试成功后回滚，不保留测试数据。
   --------------------------------------------------------- */

PRINT N'========== Positive Test P1 ==========';

BEGIN TRY
    BEGIN TRAN;

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
        9101,
        'P_VALID_TEST',
        N'合法约束测试商品',
        1,
        1,
        1,
        50.00,
        'ON_SALE'
    );

    INSERT INTO dbo.Inventory
    (
        product_id,
        on_hand_qty,
        reserved_qty,
        reorder_point
    )
    VALUES
    (
        9101,
        10,
        3,
        5
    );

    PRINT N'[PASS] P1：合法商品和库存数据插入成功。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[FAIL] P1：合法数据被错误拒绝。';
    PRINT ERROR_MESSAGE();
END CATCH;
GO



/* ---------------------------------------------------------
   正例 P2：
   合法预订满足：
       deposit_refunded <= deposit_paid

   使用独立测试编号，成功后回滚。
   --------------------------------------------------------- */

PRINT N'========== Positive Test P2 ==========';

BEGIN TRY
    BEGIN TRAN;

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
    (
        9102,
        'R_VALID_TEST',
        2,
        4,
        1,
        '2026-09-25T10:00:00',
        20.00,
        0.00,
        'ACTIVE',
        NULL
    );

    PRINT N'[PASS] P2：合法订金数据插入成功。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[FAIL] P2：合法订金数据被错误拒绝。';
    PRINT ERROR_MESSAGE();
END CATCH;
GO



/* =========================================================
   第三部分：非法数据反例
   ========================================================= */


/* =========================================================
   T1. 商品售价为负数
   验证：CHECK
   CK_Product_SalePrice
   ========================================================= */

PRINT N'========== T1：负数商品售价 ==========';

BEGIN TRY
    BEGIN TRAN;

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
        9201,
        'P_BAD_PRICE',
        N'负价格测试商品',
        1,
        NULL,
        NULL,
        -10.00,
        'ON_SALE'
    );

    PRINT N'[FAIL] T1：负数商品售价未被数据库拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T1_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T1_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T1_ErrorNumber = 547
       AND @T1_ErrorMessage LIKE N'%CK_Product_SalePrice%'
    BEGIN
        PRINT N'[PASS] T1：负数商品售价因 CK_Product_SalePrice 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T1：操作虽然失败，但并非由预期约束 CK_Product_SalePrice 导致。';
    END;

    PRINT N'错误号：' + CAST(@T1_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T1_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T2. reserved_qty > on_hand_qty
   验证：CHECK
   CK_Inventory_ReservedNotExceedOnHand
   ========================================================= */

PRINT N'========== T2：预留库存超过实际库存 ==========';

BEGIN TRY
    BEGIN TRAN;

    /* 先创建合法测试商品 */
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
        9202,
        'P_BAD_INV',
        N'非法库存测试商品',
        1,
        NULL,
        NULL,
        30.00,
        'ON_SALE'
    );

    /* 再插入非法库存 */
    INSERT INTO dbo.Inventory
    (
        product_id,
        on_hand_qty,
        reserved_qty,
        reorder_point
    )
    VALUES
    (
        9202,
        5,
        8,
        3
    );

    PRINT N'[FAIL] T2：预留库存超过实际库存的数据未被拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T2_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T2_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T2_ErrorNumber = 547
       AND @T2_ErrorMessage LIKE N'%CK_Inventory_ReservedNotExceedOnHand%'
    BEGIN
        PRINT N'[PASS] T2：非法库存因 CK_Inventory_ReservedNotExceedOnHand 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T2：操作虽然失败，但并非由预期约束 CK_Inventory_ReservedNotExceedOnHand 导致。';
    END;

    PRINT N'错误号：' + CAST(@T2_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T2_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T3. product_code 重复
   验证：UNIQUE
   UQ_Product_ProductCode

   样例数据中已经存在：
       product_code = 'P001'
   ========================================================= */

PRINT N'========== T3：重复商品业务编号 ==========';

BEGIN TRY
    BEGIN TRAN;

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
        9203,
        'P001',
        N'重复编号测试商品',
        1,
        NULL,
        NULL,
        30.00,
        'ON_SALE'
    );

    PRINT N'[FAIL] T3：重复 product_code 未被数据库拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T3_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T3_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T3_ErrorNumber IN (2601, 2627)
       AND @T3_ErrorMessage LIKE N'%UQ_Product_ProductCode%'
    BEGIN
        PRINT N'[PASS] T3：重复 product_code 因 UQ_Product_ProductCode 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T3：操作虽然失败，但并非由预期唯一约束 UQ_Product_ProductCode 导致。';
    END;

    PRINT N'错误号：' + CAST(@T3_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T3_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T4. 商品引用不存在的商品类别
   验证：FOREIGN KEY
   FK_Product_ProductCategory
   ========================================================= */

PRINT N'========== T4：不存在的商品类别 ==========';

BEGIN TRY
    BEGIN TRAN;

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
        9204,
        'P_BAD_CATEGORY',
        N'错误类别测试商品',
        999999,
        NULL,
        NULL,
        30.00,
        'ON_SALE'
    );

    PRINT N'[FAIL] T4：不存在的 category_id 未被数据库拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T4_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T4_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T4_ErrorNumber = 547
       AND @T4_ErrorMessage LIKE N'%FK_Product_ProductCategory%'
    BEGIN
        PRINT N'[PASS] T4：不存在的 category_id 因 FK_Product_ProductCategory 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T4：操作虽然失败，但并非由预期外键 FK_Product_ProductCategory 导致。';
    END;

    PRINT N'错误号：' + CAST(@T4_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T4_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T5. 商品 IP 与具体角色不一致

   已知样例：
       ip_id = 1          原神
       character_id = 3  三月七（属于 ip_id = 2）

   注意：
   ip_id = 1 单独存在；
   character_id = 3 单独也存在。

   因此普通单列外键均不会失败，
   真正拒绝该数据的是复合外键：

       FK_Product_Character_IP
       (character_id, ip_id)
       →
       CharacterInfo(character_id, ip_id)
   ========================================================= */

PRINT N'========== T5：IP 与角色组合不一致 ==========';

BEGIN TRY
    BEGIN TRAN;

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
        9205,
        'P_BAD_CHARACTER_IP',
        N'原神三月七错误组合测试',
        1,
        1,
        3,
        30.00,
        'ON_SALE'
    );

    PRINT N'[FAIL] T5：错误 IP / 角色组合未被数据库拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T5_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T5_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T5_ErrorNumber = 547
       AND @T5_ErrorMessage LIKE N'%FK_Product_Character_IP%'
    BEGIN
        PRINT N'[PASS] T5：错误 IP / 角色组合因 FK_Product_Character_IP 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T5：操作虽然失败，但并非由预期复合外键 FK_Product_Character_IP 导致。';
    END;

    PRINT N'错误号：' + CAST(@T5_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T5_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T6. 已退订金超过实际支付订金

   验证新增：
       CK_PresaleReservation_RefundNotExceedPaid

   deposit_paid     = 20
   deposit_refunded = 30
   ========================================================= */

PRINT N'========== T6：退款超过已付订金 ==========';

BEGIN TRY
    BEGIN TRAN;

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
    (
        9206,
        'R_BAD_REFUND',
        2,
        4,
        1,
        '2026-09-25T10:00:00',
        20.00,
        30.00,
        'ACTIVE',
        NULL
    );

    PRINT N'[FAIL] T6：退款金额超过已支付订金的数据未被拒绝。';

    ROLLBACK TRAN;
END TRY

BEGIN CATCH
    DECLARE @T6_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T6_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    IF @T6_ErrorNumber = 547
       AND @T6_ErrorMessage LIKE N'%CK_PresaleReservation_RefundNotExceedPaid%'
    BEGIN
        PRINT N'[PASS] T6：退款超过已付订金因 CK_PresaleReservation_RefundNotExceedPaid 被正确拒绝。';
    END
    ELSE
    BEGIN
        PRINT N'[FAIL] T6：操作虽然失败，但并非由预期约束 CK_PresaleReservation_RefundNotExceedPaid 导致。';
    END;

    PRINT N'错误号：' + CAST(@T6_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T6_ErrorMessage;
END CATCH;
GO



/* =========================================================
   T7. 每件订金高于预售价
   验证：CHECK
   CK_PresaleActivity_DepositNotExceedPrice
   ========================================================= */

PRINT N'========== T7：订金高于预售价 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PresaleActivity
    (
        presale_id, presale_code, product_id,
        start_time, end_time,
        presale_unit_price, deposit_per_unit,
        pickup_deadline,
        decision_demand_qty, extra_stock_qty, planned_purchase_qty,
        created_by, presale_status
    )
    VALUES
    (
        9207, 'PS_BAD_DEPOSIT', 1,
        '2026-11-01T00:00:00', '2026-11-10T00:00:00',
        10.00, 20.00,
        NULL,
        NULL, 0, NULL,
        3, 'PLANNED'
    );

    PRINT N'[FAIL] T7：高于预售价的订金未被数据库拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T7_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T7_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T7_ErrorNumber = 547
       AND @T7_ErrorMessage LIKE N'%CK_PresaleActivity_DepositNotExceedPrice%'
        PRINT N'[PASS] T7：订金高于预售价因 CK_PresaleActivity_DepositNotExceedPrice 被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T7：失败原因不是预期约束 CK_PresaleActivity_DepositNotExceedPrice。';

    PRINT N'错误号：' + CAST(@T7_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T7_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T8. 最晚提货期限早于预售结束时间
   验证：CHECK
   CK_PresaleActivity_PickupDeadline
   ========================================================= */

PRINT N'========== T8：提货期限早于预售结束 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PresaleActivity
    (
        presale_id, presale_code, product_id,
        start_time, end_time,
        presale_unit_price, deposit_per_unit,
        pickup_deadline,
        decision_demand_qty, extra_stock_qty, planned_purchase_qty,
        created_by, presale_status
    )
    VALUES
    (
        9208, 'PS_BAD_DEADLINE', 1,
        '2026-11-01T00:00:00', '2026-11-10T00:00:00',
        68.00, 20.00,
        '2026-11-05T00:00:00',
        NULL, 0, NULL,
        3, 'PLANNED'
    );

    PRINT N'[FAIL] T8：早于预售结束时间的提货期限未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T8_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T8_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T8_ErrorNumber = 547
       AND @T8_ErrorMessage LIKE N'%CK_PresaleActivity_PickupDeadline%'
        PRINT N'[PASS] T8：非法提货期限因 CK_PresaleActivity_PickupDeadline 被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T8：失败原因不是预期约束 CK_PresaleActivity_PickupDeadline。';

    PRINT N'错误号：' + CAST(@T8_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T8_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T9. CANCELLED 预订缺少 cancelled_at
   验证：CHECK
   CK_PresaleReservation_CancelInfo
   ========================================================= */

PRINT N'========== T9：取消状态缺少取消时间 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PresaleReservation
    (
        reservation_id, reservation_no, presale_id, member_id,
        quantity, reserved_at, deposit_paid, deposit_refunded,
        reservation_status, cancelled_at
    )
    VALUES
    (
        9209, 'R_BAD_CANCEL_TIME', 2, 4,
        1, '2026-09-25T10:00:00', 20.00, 0.00,
        'CANCELLED', NULL
    );

    PRINT N'[FAIL] T9：CANCELLED 但无 cancelled_at 的数据未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T9_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T9_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T9_ErrorNumber = 547
       AND @T9_ErrorMessage LIKE N'%CK_PresaleReservation_CancelInfo%'
        PRINT N'[PASS] T9：取消状态与取消时间不一致的数据被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T9：失败原因不是预期约束 CK_PresaleReservation_CancelInfo。';

    PRINT N'错误号：' + CAST(@T9_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T9_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T10. 预售订单会员与预订会员不一致
   验证：复合 FOREIGN KEY
   FK_SalesOrder_ReservationMember
   ========================================================= */

PRINT N'========== T10：预售订单会员与预订会员不一致 ==========';

BEGIN TRY
    BEGIN TRAN;

    /* R002(reservation_id=2) 属于 member_id=2，且尚无提货订单；这里故意写 member_id=1。 */
    INSERT INTO dbo.SalesOrder
    (
        order_id, order_no, order_type, member_id, cashier_id,
        reservation_id, order_time, order_status
    )
    VALUES
    (
        9210, 'SO_BAD_MEMBER', 'PRESALE', 1, 1,
        2, NULL, 'CREATED'
    );

    PRINT N'[FAIL] T10：预售订单会员与预订会员不一致的数据未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T10_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T10_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T10_ErrorNumber = 547
       AND @T10_ErrorMessage LIKE N'%FK_SalesOrder_ReservationMember%'
        PRINT N'[PASS] T10：会员不一致因 FK_SalesOrder_ReservationMember 被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T10：失败原因不是预期复合外键 FK_SalesOrder_ReservationMember。';

    PRINT N'错误号：' + CAST(@T10_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T10_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T11. COMPLETED 订单缺少 order_time
   验证：CHECK
   CK_SalesOrder_StatusTime
   ========================================================= */

PRINT N'========== T11：完成订单缺少交易时间 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.SalesOrder
    (
        order_id, order_no, order_type, member_id, cashier_id,
        reservation_id, order_time, order_status
    )
    VALUES
    (
        9211, 'SO_BAD_TIME', 'SPOT', NULL, 1,
        NULL, NULL, 'COMPLETED'
    );

    PRINT N'[FAIL] T11：COMPLETED 但无 order_time 的订单未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T11_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T11_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T11_ErrorNumber = 547
       AND @T11_ErrorMessage LIKE N'%CK_SalesOrder_StatusTime%'
        PRINT N'[PASS] T11：订单状态与交易时间不一致的数据被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T11：失败原因不是预期约束 CK_SalesOrder_StatusTime。';

    PRINT N'错误号：' + CAST(@T11_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T11_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T12. 非 RECEIVED 状态却填写完成验收信息
   验证：CHECK
   CK_PurchaseOrder_ReceivedInfo
   ========================================================= */

PRINT N'========== T12：采购状态与验收信息不一致 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PurchaseOrder
    (
        purchase_id, purchase_no, supplier_id, purchase_type, presale_id,
        created_by, order_time, expected_arrival,
        received_time, received_by, purchase_status
    )
    VALUES
    (
        9212, 'PO_BAD_RECEIVE_INFO', 1, 'RESTOCK', NULL,
        3, '2026-10-01T09:00:00', '2026-10-10T09:00:00',
        '2026-10-05T12:00:00', 2, 'ORDERED'
    );

    PRINT N'[FAIL] T12：非 RECEIVED 状态却填写验收信息的数据未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T12_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T12_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T12_ErrorNumber = 547
       AND @T12_ErrorMessage LIKE N'%CK_PurchaseOrder_ReceivedInfo%'
        PRINT N'[PASS] T12：采购状态与验收信息不一致的数据被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T12：失败原因不是预期约束 CK_PurchaseOrder_ReceivedInfo。';

    PRINT N'错误号：' + CAST(@T12_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T12_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T13. 预计到货时间早于下单时间
   验证：CHECK
   CK_PurchaseOrder_ExpectedArrival
   ========================================================= */

PRINT N'========== T13：预计到货早于下单 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PurchaseOrder
    (
        purchase_id, purchase_no, supplier_id, purchase_type, presale_id,
        created_by, order_time, expected_arrival,
        received_time, received_by, purchase_status
    )
    VALUES
    (
        9213, 'PO_BAD_EXPECTED_TIME', 1, 'RESTOCK', NULL,
        3, '2026-10-10T09:00:00', '2026-10-05T09:00:00',
        NULL, NULL, 'ORDERED'
    );

    PRINT N'[FAIL] T13：预计到货早于下单时间的数据未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T13_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T13_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T13_ErrorNumber = 547
       AND @T13_ErrorMessage LIKE N'%CK_PurchaseOrder_ExpectedArrival%'
        PRINT N'[PASS] T13：非法预计到货时间被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T13：失败原因不是预期约束 CK_PurchaseOrder_ExpectedArrival。';

    PRINT N'错误号：' + CAST(@T13_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T13_ErrorMessage;
END CATCH;
GO


/* =========================================================
   T14. 实际验收时间早于下单时间
   验证：CHECK
   CK_PurchaseOrder_ReceivedTime
   ========================================================= */

PRINT N'========== T14：验收时间早于下单 ==========';

BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.PurchaseOrder
    (
        purchase_id, purchase_no, supplier_id, purchase_type, presale_id,
        created_by, order_time, expected_arrival,
        received_time, received_by, purchase_status
    )
    VALUES
    (
        9214, 'PO_BAD_RECEIVED_TIME', 1, 'RESTOCK', NULL,
        3, '2026-10-10T09:00:00', '2026-10-12T09:00:00',
        '2026-10-09T09:00:00', 2, 'RECEIVED'
    );

    PRINT N'[FAIL] T14：验收时间早于下单时间的数据未被拒绝。';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    DECLARE @T14_ErrorNumber INT = ERROR_NUMBER();
    DECLARE @T14_ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    IF @T14_ErrorNumber = 547
       AND @T14_ErrorMessage LIKE N'%CK_PurchaseOrder_ReceivedTime%'
        PRINT N'[PASS] T14：非法验收时间被正确拒绝。';
    ELSE
        PRINT N'[FAIL] T14：失败原因不是预期约束 CK_PurchaseOrder_ReceivedTime。';

    PRINT N'错误号：' + CAST(@T14_ErrorNumber AS NVARCHAR(20));
    PRINT N'错误信息：' + @T14_ErrorMessage;
END CATCH;
GO


/* =========================================================
   第四部分：测试结束后的数据确认

   由于全部测试均使用事务并回滚，
   不应存在 91xx / 92xx 临时测试数据。
   ========================================================= */

SELECT *
FROM dbo.Product
WHERE product_id BETWEEN 9100 AND 9299;

SELECT *
FROM dbo.PresaleReservation
WHERE reservation_id BETWEEN 9100 AND 9299;

SELECT *
FROM dbo.PresaleActivity
WHERE presale_id BETWEEN 9100 AND 9299;

SELECT *
FROM dbo.SalesOrder
WHERE order_id BETWEEN 9100 AND 9299;

SELECT *
FROM dbo.PurchaseOrder
WHERE purchase_id BETWEEN 9100 AND 9299;
GO