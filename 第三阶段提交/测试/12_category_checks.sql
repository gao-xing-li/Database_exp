/* baseline.sql 建立四种查询共用的分类样例。 */
SET NOCOUNT ON;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App_Stage3' OR @@TRANCOUNT <> 0
    THROW 53900, N'请在第三阶段专用库的新会话中运行。', 1;
DECLARE @actual TABLE (
    category_id int, parent_category_id int NULL, category_name nvarchar(50), depth int, category_path varchar(max)
);
DECLARE @cases TABLE (category_id int PRIMARY KEY, expected_count int, expected_depth int);
INSERT @cases VALUES (90001201, 5, 2), (90001202, 2, 1), (90001203, 1, 0), (-1, 0, -1);
DECLARE @start int, @expected_count int, @expected_depth int;
DECLARE category_checks CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @cases ORDER BY category_id DESC;
OPEN category_checks;
FETCH NEXT FROM category_checks INTO @start, @expected_count, @expected_depth;
WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT @actual EXEC dbo.ListCategorySubtree @start;
    IF (SELECT COUNT(*) FROM @actual) <> @expected_count
       OR ISNULL((SELECT MAX(depth) FROM @actual), -1) <> @expected_depth
       OR EXISTS (SELECT 1 FROM @actual WHERE category_path NOT LIKE CONCAT('/', @start, '/%'))
       OR (@start = 90001201 AND NOT EXISTS (SELECT 1 FROM @actual WHERE category_id = 90001203
               AND parent_category_id = 90001202 AND depth = 2 AND category_path = '/90001201/90001202/90001203/'))
        THROW 53990, N'分类递归结果与样例层级或路径不符。', 1;
    SELECT @start AS start_category, @expected_count AS expected_count, COUNT(*) AS actual_count,
           ISNULL(MAX(depth), -1) AS max_depth FROM @actual;
    SELECT * FROM @actual ORDER BY depth, category_id;
    DELETE FROM @actual;
    FETCH NEXT FROM category_checks INTO @start, @expected_count, @expected_depth;
END;
CLOSE category_checks;
DEALLOCATE category_checks;
SELECT N'PASS' AS status, N'B 第 12 周分类递归' AS suite;
