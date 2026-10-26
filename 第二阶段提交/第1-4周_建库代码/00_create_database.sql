/* =========================================================
   00_create_database.sql
   二次元周边商品店数据库

   兼容首次运行与完整链重复运行：
   - 数据库不存在：创建 AnimeGoodsStoreDB
   - 数据库已存在：直接复用数据库
   - 业务表 / 视图的重建由 01_create_tables.sql 负责
   ========================================================= */

IF DB_ID(N'AnimeGoodsStoreDB') IS NULL
BEGIN
    CREATE DATABASE AnimeGoodsStoreDB;
    PRINT N'AnimeGoodsStoreDB 已创建。';
END
ELSE
BEGIN
    PRINT N'AnimeGoodsStoreDB 已存在，将复用现有数据库。';
END;
GO

USE AnimeGoodsStoreDB;
GO
