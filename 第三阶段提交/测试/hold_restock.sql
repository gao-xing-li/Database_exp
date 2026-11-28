/* 第13周交接。一次只选中执行一个区块，在同一窗口完成 B1、B2。
   在另一窗口连接同一数据库并查询 @@SPID，使用不同会话观察等待或读现象。 */

-- B1 从此行选到本区块结束。90013101 是 P×5，90013102 是 P×5、Q×3。
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3' OR @@TRANCOUNT <> 0
    THROW 53900, N'请先切到第三阶段专用库，并清理会话事务。', 1;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.ReceiveRestock @purchase_id = 90013101, @employee_id = 2;
    SELECT @@SPID AS session_id, @@TRANCOUNT AS pending_transactions, XACT_STATE() AS transaction_state;
    SELECT product_id, on_hand_qty, reserved_qty FROM dbo.Inventory WHERE product_id = 90001301;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
-- B1 结束。此时外层事务仍开启，库存、单据和审计变动等候同一次提交。

-- B2 在相同的窗口选中执行下一条 COMMIT 或 ROLLBACK，按场景二选一。
-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;
-- SELECT @@SPID AS session_id, @@TRANCOUNT AS pending_transactions, XACT_STATE() AS transaction_state;
