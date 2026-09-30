/* =========================================================
   00_create_database.sql
   二次元周边商品店数据库
   ========================================================= */

IF DB_ID(N'AnimeGoodsStoreDB') IS NULL
BEGIN
    CREATE DATABASE AnimeGoodsStoreDB;
END;
GO

USE AnimeGoodsStoreDB;
GO