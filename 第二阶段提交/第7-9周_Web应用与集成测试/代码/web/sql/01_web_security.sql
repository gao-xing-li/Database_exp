/* 在已完成第六周迁移的独立样例库执行。登录由 init_demo.py 创建。
   没有 DROP/重建业务表，没有修改原有角色授权。
   Web 使用本文件的新角色，与第一阶段 WITHOUT LOGIN 测试用户分离。 */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'UX_PurchaseOrder_PresaleID')
    THROW 51200,N'请先完成第六周迁移。',1;
IF OBJECT_ID(N'dbo.WebUser') IS NOT NULL
    THROW 51201,N'Web 认证结构已存在，不重复初始化。',1;

CREATE TABLE dbo.WebUser (
    user_id int IDENTITY PRIMARY KEY,
    username varchar(50) NOT NULL UNIQUE,
    password_hash varchar(255) NOT NULL,
    role varchar(20) NOT NULL,
    employee_id int NULL REFERENCES dbo.Employee(employee_id),
    member_id int NULL REFERENCES dbo.Member(member_id),
    is_active bit NOT NULL DEFAULT 1,
    CONSTRAINT CK_WebUser_Identity CHECK (
        (role IN ('manager','clerk','inventory') AND employee_id IS NOT NULL AND member_id IS NULL)
        OR (role='customer' AND employee_id IS NULL AND member_id IS NOT NULL))
);
CREATE ROLE web_auth;
CREATE ROLE web_manager;
CREATE ROLE web_clerk;
CREATE ROLE web_inventory;
CREATE ROLE web_customer;

GRANT SELECT ON dbo.WebUser TO web_auth;
GRANT SELECT ON dbo.Member TO web_auth;
GRANT SELECT ON dbo.Employee TO web_auth;
GRANT SELECT ON dbo.BusinessRole TO web_auth;

GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.Product TO web_manager;
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.Inventory TO web_manager;
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.SalesOrder TO web_manager;
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.SalesOrderItem TO web_manager;
GRANT SELECT ON dbo.Member TO web_manager;

GRANT SELECT ON dbo.Product TO web_clerk;
GRANT SELECT ON dbo.Inventory TO web_clerk;
GRANT UPDATE (on_hand_qty,updated_at) ON dbo.Inventory TO web_clerk;
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.SalesOrder TO web_clerk;
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.SalesOrderItem TO web_clerk;
GRANT SELECT ON dbo.Member TO web_clerk;

GRANT SELECT ON dbo.Product TO web_inventory;
GRANT SELECT,INSERT ON dbo.Inventory TO web_inventory;
GRANT UPDATE (on_hand_qty,reorder_point,updated_at) ON dbo.Inventory TO web_inventory;

GRANT SELECT ON dbo.Product TO web_customer;
GRANT SELECT ON dbo.Inventory TO web_customer;
GRANT SELECT ON dbo.SalesOrder TO web_customer;
GRANT SELECT ON dbo.SalesOrderItem TO web_customer;
GO
CREATE FUNCTION dbo.WebOrderAccess(@member_id int)
RETURNS TABLE WITH SCHEMABINDING AS RETURN
    SELECT 1 AS allowed WHERE USER_NAME() <> N'course_customer'
       OR @member_id = TRY_CONVERT(int, SESSION_CONTEXT(N'member_id'));
GO
CREATE FUNCTION dbo.WebItemAccess(@order_id int)
RETURNS TABLE WITH SCHEMABINDING AS RETURN
    SELECT 1 AS allowed WHERE USER_NAME() <> N'course_customer'
       OR EXISTS (SELECT 1 FROM dbo.SalesOrder o WHERE o.order_id=@order_id
                  AND o.member_id=TRY_CONVERT(int,SESSION_CONTEXT(N'member_id')));
GO
CREATE SECURITY POLICY dbo.WebOrderPolicy
ADD FILTER PREDICATE dbo.WebOrderAccess(member_id) ON dbo.SalesOrder,
ADD FILTER PREDICATE dbo.WebItemAccess(order_id) ON dbo.SalesOrderItem
WITH (STATE=ON);
GO
