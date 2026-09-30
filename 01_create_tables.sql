/* =========================================================
   01_create_tables.sql
   二次元周边商品店：创建数据表与基础完整性约束

   执行前请先执行：
   00_create_database.sql
   ========================================================= */

USE AnimeGoodsStoreDB;
GO


/* =========================================================
   1. ProductCategory 商品类别
   ========================================================= */

CREATE TABLE dbo.ProductCategory
(
    category_id INT NOT NULL,
    category_name NVARCHAR(50) NOT NULL,
    description NVARCHAR(200) NULL,

    CONSTRAINT PK_ProductCategory
        PRIMARY KEY (category_id),

    CONSTRAINT UQ_ProductCategory_CategoryName
        UNIQUE (category_name),

    CONSTRAINT CK_ProductCategory_CategoryID
        CHECK (category_id > 0)
);
GO


/* =========================================================
   2. AnimeIP 作品 / IP
   ========================================================= */

CREATE TABLE dbo.AnimeIP
(
    ip_id INT NOT NULL,
    ip_name NVARCHAR(100) NOT NULL,
    description NVARCHAR(200) NULL,

    CONSTRAINT PK_AnimeIP
        PRIMARY KEY (ip_id),

    CONSTRAINT UQ_AnimeIP_IPName
        UNIQUE (ip_name),

    CONSTRAINT CK_AnimeIP_IPID
        CHECK (ip_id > 0)
);
GO


/* =========================================================
   3. BusinessRole 员工业务角色
   注意：这里是现实经营角色，不是 SQL Server 权限角色
   ========================================================= */

CREATE TABLE dbo.BusinessRole
(
    role_id INT NOT NULL,
    role_name NVARCHAR(50) NOT NULL,
    description NVARCHAR(200) NULL,

    CONSTRAINT PK_BusinessRole
        PRIMARY KEY (role_id),

    CONSTRAINT UQ_BusinessRole_RoleName
        UNIQUE (role_name),

    CONSTRAINT CK_BusinessRole_RoleID
        CHECK (role_id > 0)
);
GO


/* =========================================================
   4. Member 会员
   ========================================================= */

CREATE TABLE dbo.Member
(
    member_id INT NOT NULL,
    member_no VARCHAR(20) NOT NULL,
    member_name NVARCHAR(50) NOT NULL,
    phone VARCHAR(20) NOT NULL,

    register_time DATETIME2 NOT NULL
        CONSTRAINT DF_Member_RegisterTime
        DEFAULT SYSDATETIME(),

    member_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Member_Status
        DEFAULT ('ACTIVE'),

    CONSTRAINT PK_Member
        PRIMARY KEY (member_id),

    CONSTRAINT UQ_Member_MemberNo
        UNIQUE (member_no),

    CONSTRAINT UQ_Member_Phone
        UNIQUE (phone),

    CONSTRAINT CK_Member_MemberID
        CHECK (member_id > 0),

    CONSTRAINT CK_Member_Status
        CHECK (member_status IN ('ACTIVE', 'INACTIVE'))
);
GO


/* =========================================================
   5. Supplier 供应商
   ========================================================= */

CREATE TABLE dbo.Supplier
(
    supplier_id INT NOT NULL,
    supplier_code VARCHAR(20) NOT NULL,
    supplier_name NVARCHAR(100) NOT NULL,
    contact_name NVARCHAR(50) NULL,
    phone VARCHAR(20) NULL,

    supplier_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Supplier_Status
        DEFAULT ('ACTIVE'),

    CONSTRAINT PK_Supplier
        PRIMARY KEY (supplier_id),

    CONSTRAINT UQ_Supplier_SupplierCode
        UNIQUE (supplier_code),

    CONSTRAINT CK_Supplier_SupplierID
        CHECK (supplier_id > 0),

    CONSTRAINT CK_Supplier_Status
        CHECK (supplier_status IN ('ACTIVE', 'INACTIVE'))
);
GO


/* =========================================================
   6. CharacterInfo 角色
   ========================================================= */

CREATE TABLE dbo.CharacterInfo
(
    character_id INT NOT NULL,
    ip_id INT NOT NULL,
    character_name NVARCHAR(100) NOT NULL,

    CONSTRAINT PK_CharacterInfo
        PRIMARY KEY (character_id),

    -- 同一 IP 下角色名称不能重复
    CONSTRAINT UQ_CharacterInfo_IP_CharacterName
        UNIQUE (ip_id, character_name),

    -- 为 Product 中的复合外键提供候选键
    CONSTRAINT UQ_CharacterInfo_CharacterID_IP
        UNIQUE (character_id, ip_id),

    CONSTRAINT FK_CharacterInfo_AnimeIP
        FOREIGN KEY (ip_id)
        REFERENCES dbo.AnimeIP(ip_id),

    CONSTRAINT CK_CharacterInfo_CharacterID
        CHECK (character_id > 0)
);
GO


/* =========================================================
   7. Employee 员工
   ========================================================= */

CREATE TABLE dbo.Employee
(
    employee_id INT NOT NULL,
    employee_no VARCHAR(20) NOT NULL,
    employee_name NVARCHAR(50) NOT NULL,
    role_id INT NOT NULL,
    phone VARCHAR(20) NULL,
    hire_date DATE NOT NULL,

    employee_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Employee_Status
        DEFAULT ('ACTIVE'),

    CONSTRAINT PK_Employee
        PRIMARY KEY (employee_id),

    CONSTRAINT UQ_Employee_EmployeeNo
        UNIQUE (employee_no),

    CONSTRAINT FK_Employee_BusinessRole
        FOREIGN KEY (role_id)
        REFERENCES dbo.BusinessRole(role_id),

    CONSTRAINT CK_Employee_EmployeeID
        CHECK (employee_id > 0),

    CONSTRAINT CK_Employee_Status
        CHECK (employee_status IN ('ACTIVE', 'INACTIVE'))
);
GO


/* =========================================================
   8. Product 商品
   ========================================================= */

CREATE TABLE dbo.Product
(
    product_id INT NOT NULL,
    product_code VARCHAR(20) NOT NULL,
    product_name NVARCHAR(150) NOT NULL,

    category_id INT NOT NULL,
    ip_id INT NULL,
    character_id INT NULL,

    sale_price DECIMAL(10,2) NOT NULL,

    product_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Product_Status
        DEFAULT ('ON_SALE'),

    created_at DATETIME2 NOT NULL
        CONSTRAINT DF_Product_CreatedAt
        DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Product
        PRIMARY KEY (product_id),

    CONSTRAINT UQ_Product_ProductCode
        UNIQUE (product_code),

    CONSTRAINT FK_Product_ProductCategory
        FOREIGN KEY (category_id)
        REFERENCES dbo.ProductCategory(category_id),

    CONSTRAINT FK_Product_AnimeIP
        FOREIGN KEY (ip_id)
        REFERENCES dbo.AnimeIP(ip_id),

    CONSTRAINT FK_Product_CharacterInfo
        FOREIGN KEY (character_id)
        REFERENCES dbo.CharacterInfo(character_id),

    -- 保证角色和 IP 属于同一个角色记录
    CONSTRAINT FK_Product_Character_IP
        FOREIGN KEY (character_id, ip_id)
        REFERENCES dbo.CharacterInfo(character_id, ip_id),

    CONSTRAINT CK_Product_ProductID
        CHECK (product_id > 0),

    CONSTRAINT CK_Product_SalePrice
        CHECK (sale_price > 0),

    CONSTRAINT CK_Product_Status
        CHECK (
            product_status IN
            ('PENDING', 'ON_SALE', 'STOPPED')
        ),

    -- 如果指定具体角色，就必须同时指定 IP
    CONSTRAINT CK_Product_CharacterRequiresIP
        CHECK (
            character_id IS NULL
            OR ip_id IS NOT NULL
        )
);
GO


/* =========================================================
   9. Inventory 库存
   ========================================================= */

CREATE TABLE dbo.Inventory
(
    product_id INT NOT NULL,

    on_hand_qty INT NOT NULL
        CONSTRAINT DF_Inventory_OnHandQty
        DEFAULT (0),

    reserved_qty INT NOT NULL
        CONSTRAINT DF_Inventory_ReservedQty
        DEFAULT (0),

    reorder_point INT NOT NULL
        CONSTRAINT DF_Inventory_ReorderPoint
        DEFAULT (0),

    updated_at DATETIME2 NOT NULL
        CONSTRAINT DF_Inventory_UpdatedAt
        DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Inventory
        PRIMARY KEY (product_id),

    CONSTRAINT FK_Inventory_Product
        FOREIGN KEY (product_id)
        REFERENCES dbo.Product(product_id),

    CONSTRAINT CK_Inventory_OnHandQty
        CHECK (on_hand_qty >= 0),

    CONSTRAINT CK_Inventory_ReservedQty
        CHECK (reserved_qty >= 0),

    CONSTRAINT CK_Inventory_ReorderPoint
        CHECK (reorder_point >= 0),

    CONSTRAINT CK_Inventory_ReservedNotExceedOnHand
        CHECK (reserved_qty <= on_hand_qty)
);
GO


/* =========================================================
   10. PresaleActivity 预售活动
   ========================================================= */

CREATE TABLE dbo.PresaleActivity
(
    presale_id INT NOT NULL,
    presale_code VARCHAR(20) NOT NULL,

    product_id INT NOT NULL,

    start_time DATETIME2 NOT NULL,
    end_time DATETIME2 NOT NULL,

    presale_unit_price DECIMAL(10,2) NOT NULL,
    deposit_per_unit DECIMAL(10,2) NOT NULL,

    pickup_deadline DATETIME2 NULL,

    decision_demand_qty INT NULL,

    extra_stock_qty INT NOT NULL
        CONSTRAINT DF_PresaleActivity_ExtraStockQty
        DEFAULT (0),

    planned_purchase_qty INT NULL,

    created_by INT NOT NULL,

    presale_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_PresaleActivity_Status
        DEFAULT ('PLANNED'),

    CONSTRAINT PK_PresaleActivity
        PRIMARY KEY (presale_id),

    CONSTRAINT UQ_PresaleActivity_PresaleCode
        UNIQUE (presale_code),

    CONSTRAINT FK_PresaleActivity_Product
        FOREIGN KEY (product_id)
        REFERENCES dbo.Product(product_id),

    CONSTRAINT FK_PresaleActivity_Employee
        FOREIGN KEY (created_by)
        REFERENCES dbo.Employee(employee_id),

    CONSTRAINT CK_PresaleActivity_PresaleID
        CHECK (presale_id > 0),

    CONSTRAINT CK_PresaleActivity_Time
        CHECK (start_time < end_time),

    CONSTRAINT CK_PresaleActivity_UnitPrice
        CHECK (presale_unit_price > 0),

    CONSTRAINT CK_PresaleActivity_Deposit
        CHECK (deposit_per_unit >= 0),

    CONSTRAINT CK_PresaleActivity_DecisionDemand
        CHECK (
            decision_demand_qty IS NULL
            OR decision_demand_qty >= 0
        ),

    CONSTRAINT CK_PresaleActivity_ExtraStock
        CHECK (extra_stock_qty >= 0),

    CONSTRAINT CK_PresaleActivity_PlannedPurchase
        CHECK (
            planned_purchase_qty IS NULL
            OR planned_purchase_qty >= 0
        ),

    CONSTRAINT CK_PresaleActivity_Status
        CHECK (
            presale_status IN
            (
                'PLANNED',
                'OPEN',
                'CLOSED',
                'PURCHASING',
                'ARRIVED',
                'FINISHED'
            )
        )
);
GO


/* =========================================================
   11. PresaleReservation 预售预订
   ========================================================= */

CREATE TABLE dbo.PresaleReservation
(
    reservation_id INT NOT NULL,
    reservation_no VARCHAR(20) NOT NULL,

    presale_id INT NOT NULL,
    member_id INT NOT NULL,

    quantity INT NOT NULL,

    reserved_at DATETIME2 NOT NULL
        CONSTRAINT DF_PresaleReservation_ReservedAt
        DEFAULT SYSDATETIME(),

    deposit_paid DECIMAL(10,2) NOT NULL,

    deposit_refunded DECIMAL(10,2) NOT NULL
        CONSTRAINT DF_PresaleReservation_DepositRefunded
        DEFAULT (0),

    reservation_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_PresaleReservation_Status
        DEFAULT ('ACTIVE'),

    cancelled_at DATETIME2 NULL,

    CONSTRAINT PK_PresaleReservation
        PRIMARY KEY (reservation_id),

    CONSTRAINT UQ_PresaleReservation_ReservationNo
        UNIQUE (reservation_no),

    CONSTRAINT FK_PresaleReservation_PresaleActivity
        FOREIGN KEY (presale_id)
        REFERENCES dbo.PresaleActivity(presale_id),

    CONSTRAINT FK_PresaleReservation_Member
        FOREIGN KEY (member_id)
        REFERENCES dbo.Member(member_id),

    CONSTRAINT CK_PresaleReservation_ReservationID
        CHECK (reservation_id > 0),

    CONSTRAINT CK_PresaleReservation_Quantity
        CHECK (quantity > 0),

    CONSTRAINT CK_PresaleReservation_DepositPaid
        CHECK (deposit_paid >= 0),

    CONSTRAINT CK_PresaleReservation_DepositRefunded
        CHECK (deposit_refunded >= 0),

    CONSTRAINT CK_PresaleReservation_Status
        CHECK (
            reservation_status IN
            (
                'ACTIVE',
                'CANCELLED',
                'PICKED_UP',
                'EXPIRED'
            )
        )
);
GO


/* =========================================================
   12. PurchaseOrder 采购订单
   ========================================================= */

CREATE TABLE dbo.PurchaseOrder
(
    purchase_id INT NOT NULL,
    purchase_no VARCHAR(20) NOT NULL,

    supplier_id INT NOT NULL,

    purchase_type VARCHAR(20) NOT NULL,

    presale_id INT NULL,

    created_by INT NOT NULL,

    order_time DATETIME2 NOT NULL
        CONSTRAINT DF_PurchaseOrder_OrderTime
        DEFAULT SYSDATETIME(),

    expected_arrival DATETIME2 NULL,
    received_time DATETIME2 NULL,
    received_by INT NULL,

    purchase_status VARCHAR(30) NOT NULL
        CONSTRAINT DF_PurchaseOrder_Status
        DEFAULT ('CREATED'),

    CONSTRAINT PK_PurchaseOrder
        PRIMARY KEY (purchase_id),

    CONSTRAINT UQ_PurchaseOrder_PurchaseNo
        UNIQUE (purchase_no),

    CONSTRAINT FK_PurchaseOrder_Supplier
        FOREIGN KEY (supplier_id)
        REFERENCES dbo.Supplier(supplier_id),

    CONSTRAINT FK_PurchaseOrder_PresaleActivity
        FOREIGN KEY (presale_id)
        REFERENCES dbo.PresaleActivity(presale_id),

    CONSTRAINT FK_PurchaseOrder_CreatedBy
        FOREIGN KEY (created_by)
        REFERENCES dbo.Employee(employee_id),

    CONSTRAINT FK_PurchaseOrder_ReceivedBy
        FOREIGN KEY (received_by)
        REFERENCES dbo.Employee(employee_id),

    CONSTRAINT CK_PurchaseOrder_PurchaseID
        CHECK (purchase_id > 0),

    CONSTRAINT CK_PurchaseOrder_Type
        CHECK (
            purchase_type IN ('RESTOCK', 'PRESALE')
        ),

    CONSTRAINT CK_PurchaseOrder_Status
        CHECK (
            purchase_status IN
            (
                'CREATED',
                'ORDERED',
                'PARTIAL_RECEIVED',
                'RECEIVED',
                'CANCELLED'
            )
        ),

    -- 预售采购必须明确关联一场预售活动
    CONSTRAINT CK_PurchaseOrder_PresaleRequired
        CHECK (
            purchase_type <> 'PRESALE'
            OR presale_id IS NOT NULL
        ),

    -- 如果订单已经标记为完整验收，
    -- 则验收时间和验收员工必须存在
    CONSTRAINT CK_PurchaseOrder_ReceivedInfo
        CHECK (
            purchase_status <> 'RECEIVED'
            OR
            (
                received_time IS NOT NULL
                AND received_by IS NOT NULL
            )
        )
);
GO


/* =========================================================
   13. PurchaseOrderItem 采购订单明细
   ========================================================= */

CREATE TABLE dbo.PurchaseOrderItem
(
    purchase_id INT NOT NULL,
    product_id INT NOT NULL,

    ordered_qty INT NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,

    received_qty INT NOT NULL
        CONSTRAINT DF_PurchaseOrderItem_ReceivedQty
        DEFAULT (0),

    CONSTRAINT PK_PurchaseOrderItem
        PRIMARY KEY (purchase_id, product_id),

    CONSTRAINT FK_PurchaseOrderItem_PurchaseOrder
        FOREIGN KEY (purchase_id)
        REFERENCES dbo.PurchaseOrder(purchase_id),

    CONSTRAINT FK_PurchaseOrderItem_Product
        FOREIGN KEY (product_id)
        REFERENCES dbo.Product(product_id),

    CONSTRAINT CK_PurchaseOrderItem_OrderedQty
        CHECK (ordered_qty > 0),

    CONSTRAINT CK_PurchaseOrderItem_UnitCost
        CHECK (unit_cost > 0),

    CONSTRAINT CK_PurchaseOrderItem_ReceivedQty
        CHECK (
            received_qty >= 0
            AND received_qty <= ordered_qty
        )
);
GO


/* =========================================================
   14. SalesOrder 销售订单
   ========================================================= */

CREATE TABLE dbo.SalesOrder
(
    order_id INT NOT NULL,
    order_no VARCHAR(20) NOT NULL,

    order_type VARCHAR(20) NOT NULL,

    member_id INT NULL,
    cashier_id INT NOT NULL,

    reservation_id INT NULL,

    order_time DATETIME2 NULL,

    order_status VARCHAR(20) NOT NULL
        CONSTRAINT DF_SalesOrder_Status
        DEFAULT ('CREATED'),

    CONSTRAINT PK_SalesOrder
        PRIMARY KEY (order_id),

    CONSTRAINT UQ_SalesOrder_OrderNo
        UNIQUE (order_no),

    CONSTRAINT FK_SalesOrder_Member
        FOREIGN KEY (member_id)
        REFERENCES dbo.Member(member_id),

    CONSTRAINT FK_SalesOrder_Cashier
        FOREIGN KEY (cashier_id)
        REFERENCES dbo.Employee(employee_id),

    CONSTRAINT FK_SalesOrder_PresaleReservation
        FOREIGN KEY (reservation_id)
        REFERENCES dbo.PresaleReservation(reservation_id),

    CONSTRAINT CK_SalesOrder_OrderID
        CHECK (order_id > 0),

    CONSTRAINT CK_SalesOrder_Type
        CHECK (
            order_type IN ('SPOT', 'PRESALE')
        ),

    CONSTRAINT CK_SalesOrder_Status
        CHECK (
            order_status IN
            ('CREATED', 'COMPLETED', 'CANCELLED')
        ),

    /*
       SPOT：
       reservation_id 必须为空；
       member_id 可以为空，也可以指向会员。

       PRESALE：
       reservation_id 和 member_id 均不能为空。
    */
    CONSTRAINT CK_SalesOrder_TypeFields
        CHECK
        (
            (
                order_type = 'SPOT'
                AND reservation_id IS NULL
            )
            OR
            (
                order_type = 'PRESALE'
                AND reservation_id IS NOT NULL
                AND member_id IS NOT NULL
            )
        )
);
GO


/*
   一条非空 reservation_id
   最多只能对应一笔销售订单。

   不能直接给 reservation_id 加普通 UNIQUE，
   否则会影响多笔 reservation_id = NULL 的普通订单。
*/
CREATE UNIQUE INDEX UX_SalesOrder_ReservationID
ON dbo.SalesOrder(reservation_id)
WHERE reservation_id IS NOT NULL;
GO


/* =========================================================
   15. SalesOrderItem 销售订单明细
   ========================================================= */

CREATE TABLE dbo.SalesOrderItem
(
    order_id INT NOT NULL,
    product_id INT NOT NULL,

    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    CONSTRAINT PK_SalesOrderItem
        PRIMARY KEY (order_id, product_id),

    CONSTRAINT FK_SalesOrderItem_SalesOrder
        FOREIGN KEY (order_id)
        REFERENCES dbo.SalesOrder(order_id),

    CONSTRAINT FK_SalesOrderItem_Product
        FOREIGN KEY (product_id)
        REFERENCES dbo.Product(product_id),

    CONSTRAINT CK_SalesOrderItem_Quantity
        CHECK (quantity > 0),

    CONSTRAINT CK_SalesOrderItem_UnitPrice
        CHECK (unit_price > 0)
);
GO