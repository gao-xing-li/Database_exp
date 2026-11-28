/* 第10周 B：补货量；A 的销售汇总与折扣函数在合并时加入本文件。 */
CREATE OR ALTER FUNCTION dbo.RestockQuantity(@product_id int, @target_qty int = NULL)
RETURNS int
AS
BEGIN
    IF @target_qty < 0 RETURN NULL;
    DECLARE @gap int;
    SELECT @gap = COALESCE(@target_qty, i.reorder_point, 0)
                  - (COALESCE(i.on_hand_qty, 0) - COALESCE(i.reserved_qty, 0))
    FROM dbo.Product AS p
    LEFT JOIN dbo.Inventory AS i ON i.product_id = p.product_id
    WHERE p.product_id = @product_id;

    IF @gap IS NULL RETURN NULL;
    RETURN IIF(@gap > 0, @gap, 0);
END;
GO
GRANT EXECUTE ON dbo.RestockQuantity TO web_manager, web_inventory;
GO
