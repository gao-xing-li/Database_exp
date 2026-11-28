/* 第12周 B：既有分类默认仍为根分类，按需为分类指定父级。 */
IF COL_LENGTH(N'dbo.ProductCategory', N'parent_category_id') IS NULL
    ALTER TABLE dbo.ProductCategory ADD parent_category_id int NULL;
GO
IF OBJECT_ID(N'dbo.FK_ProductCategory_Parent', N'F') IS NULL
    ALTER TABLE dbo.ProductCategory WITH CHECK
        ADD CONSTRAINT FK_ProductCategory_Parent FOREIGN KEY (parent_category_id)
        REFERENCES dbo.ProductCategory(category_id);
IF OBJECT_ID(N'dbo.CK_ProductCategory_Parent', N'C') IS NULL
    ALTER TABLE dbo.ProductCategory WITH CHECK
        ADD CONSTRAINT CK_ProductCategory_Parent CHECK (parent_category_id <> category_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ProductCategory')
               AND name = N'IX_ProductCategory_Parent')
    CREATE INDEX IX_ProductCategory_Parent ON dbo.ProductCategory(parent_category_id);
GO
CREATE OR ALTER PROCEDURE dbo.ListCategorySubtree
    @category_id int
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH subtree AS (
        SELECT category_id, parent_category_id, category_name, 0 AS depth,
               CAST(CONCAT('/', category_id, '/') AS varchar(max)) AS category_path
        FROM dbo.ProductCategory
        WHERE category_id = @category_id
        UNION ALL
        SELECT c.category_id, c.parent_category_id, c.category_name, s.depth + 1,
               CAST(CONCAT(s.category_path, c.category_id, '/') AS varchar(max))
        FROM dbo.ProductCategory AS c
        JOIN subtree AS s ON c.parent_category_id = s.category_id
        WHERE CHARINDEX(CONCAT('/', c.category_id, '/'), s.category_path) = 0
    )
    SELECT category_id, parent_category_id, category_name, depth, category_path
    FROM subtree
    ORDER BY depth, category_id
    OPTION (MAXRECURSION 100);
END;
GO
