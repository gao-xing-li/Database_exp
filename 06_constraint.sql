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
   3. T1-T6 非法数据反例测试

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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T1：负数商品售价被正确拒绝。';
    PRINT ERROR_MESSAGE();
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T2：预留库存超过实际库存的数据被正确拒绝。';
    PRINT ERROR_MESSAGE();
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T3：重复 product_code 被 UNIQUE 约束正确拒绝。';
    PRINT ERROR_MESSAGE();
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T4：不存在的 category_id 被外键正确拒绝。';
    PRINT ERROR_MESSAGE();
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T5：错误 IP / 角色组合被复合外键正确拒绝。';
    PRINT ERROR_MESSAGE();
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    PRINT N'[PASS] T6：退款金额超过已支付订金的数据被正确拒绝。';
    PRINT ERROR_MESSAGE();
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
GO