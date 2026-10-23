"""参数均经绑定传入，SQL 的表名、字段和排序固定，不接受外部 SQL 片段。"""
class Repository:
    def __init__(self, cursor):
        self.cursor = cursor

    def all(self, sql, params=()):
        self.cursor.execute(sql, params)
        return self.cursor.fetchall()

    def one(self, sql, params=()):
        self.cursor.execute(sql, params)
        return self.cursor.fetchone()

    def execute(self, sql, params=()):
        self.cursor.execute(sql, params)
        return self.cursor.rowcount

    def user_by_name(self, username):
        return self.one("SELECT * FROM dbo.WebUser WHERE username=%s", (username,))

    def user_by_id(self, user_id):
        return self.one("SELECT * FROM dbo.WebUser WHERE user_id=%s", (user_id,))

    def employee(self, employee_id):
        return self.one("SELECT e.employee_status, r.role_name FROM dbo.Employee e "
                        "JOIN dbo.BusinessRole r ON r.role_id=e.role_id "
                        "WHERE employee_id=%s", (employee_id,))

    def member(self, member_id):
        return self.one("SELECT member_id,member_no,member_name,member_status "
                        "FROM dbo.Member WHERE member_id=%s", (member_id,))

    def lookups(self, staff):
        result = {
            "categories": self.all("SELECT category_id,category_name FROM dbo.ProductCategory ORDER BY category_id"),
            "ips": self.all("SELECT ip_id,ip_name FROM dbo.AnimeIP ORDER BY ip_id"),
            "characters": self.all("SELECT character_id,ip_id,character_name FROM dbo.CharacterInfo ORDER BY character_id"),
        }
        result["members"] = self.all("SELECT member_id,member_no,member_name FROM dbo.Member "
                                     "WHERE member_status='ACTIVE' ORDER BY member_id") if staff else []
        return result

    def products(self, term, staff):
        return self.all("SELECT TOP (200) p.*, c.category_name, a.ip_name, ch.character_name, "
                        "i.on_hand_qty,i.reserved_qty,i.reorder_point, "
                        "i.on_hand_qty-i.reserved_qty AS available_qty "
                        "FROM dbo.Product p JOIN dbo.ProductCategory c ON c.category_id=p.category_id "
                        "LEFT JOIN dbo.AnimeIP a ON a.ip_id=p.ip_id "
                        "LEFT JOIN dbo.CharacterInfo ch ON ch.character_id=p.character_id "
                        "LEFT JOIN dbo.Inventory i ON i.product_id=p.product_id "
                        "WHERE (p.product_name LIKE %s OR p.product_code LIKE %s) "
                        "AND (%s=1 OR p.product_status='ON_SALE') ORDER BY p.product_id", (term, term, int(staff)))

    def product(self, product_id, lock=False):
        if lock:
            return self.one("SELECT * FROM dbo.Product WITH (UPDLOCK,HOLDLOCK) WHERE product_id=%s", (product_id,))
        return self.one("SELECT * FROM dbo.Product WHERE product_id=%s", (product_id,))

    def create_product(self, values):
        row = self.one("SELECT NEXT VALUE FOR dbo.WebProductSeq AS id")
        self.execute("INSERT dbo.Product (product_id,product_code,product_name,category_id,ip_id,character_id,"
                     "sale_price,product_status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)", (row["id"], *values))
        self.execute("INSERT dbo.Inventory (product_id) VALUES (%s)", (row["id"],))
        return row["id"]

    def update_product(self, product_id, values):
        return self.execute("UPDATE dbo.Product SET product_code=%s,product_name=%s,category_id=%s,ip_id=%s,"
                            "character_id=%s,sale_price=%s,product_status=%s WHERE product_id=%s", (*values, product_id))

    def delete_product(self, product_id):
        self.execute("DELETE dbo.Inventory WHERE product_id=%s", (product_id,))
        self.execute("DELETE dbo.Product WHERE product_id=%s", (product_id,))

    def inventory(self, product_id):
        return self.one("SELECT * FROM dbo.Inventory WITH (UPDLOCK,HOLDLOCK) WHERE product_id=%s", (product_id,))

    def init_inventory(self, product_id):
        self.execute("INSERT dbo.Inventory (product_id) VALUES (%s)", (product_id,))

    def adjust_inventory(self, product_id, delta, reorder_point):
        self.execute("UPDATE dbo.Inventory SET on_hand_qty=on_hand_qty+%s,reorder_point=%s,updated_at=SYSDATETIME() "
                     "WHERE product_id=%s", (delta, reorder_point, product_id))

    def orders(self, member_id=None):
        return self.all("SELECT TOP (200) o.order_id,o.order_no,o.order_type,o.member_id,o.cashier_id,"
                        "o.order_time,o.order_status,COUNT(i.product_id) AS item_count,"
                        "COALESCE(SUM(i.quantity*i.unit_price),0) AS amount "
                        "FROM dbo.SalesOrder o LEFT JOIN dbo.SalesOrderItem i ON i.order_id=o.order_id "
                        "WHERE (%s IS NULL OR o.member_id=%s) "
                        "GROUP BY o.order_id,o.order_no,o.order_type,o.member_id,o.cashier_id,o.order_time,o.order_status "
                        "ORDER BY o.order_id DESC", (member_id, member_id))

    def order(self, order_id, lock=False):
        if lock:
            return self.one("SELECT * FROM dbo.SalesOrder WITH (UPDLOCK,HOLDLOCK) WHERE order_id=%s", (order_id,))
        return self.one("SELECT * FROM dbo.SalesOrder WHERE order_id=%s", (order_id,))

    def items(self, order_id):
        return self.all("SELECT i.*,p.product_name,p.product_code,i.quantity*i.unit_price AS amount "
                        "FROM dbo.SalesOrderItem i JOIN dbo.Product p ON p.product_id=i.product_id "
                        "WHERE order_id=%s ORDER BY i.product_id", (order_id,))

    def create_order(self, member_id, cashier_id):
        order_id = self.one("SELECT NEXT VALUE FOR dbo.WebOrderSeq AS id")["id"]
        order_no = f"WEB{order_id:010d}"
        self.execute("INSERT dbo.SalesOrder (order_id,order_no,order_type,member_id,cashier_id) "
                     "VALUES (%s,%s,'SPOT',%s,%s)", (order_id, order_no, member_id, cashier_id))
        return order_id

    def update_order(self, order_id, member_id):
        self.execute("UPDATE dbo.SalesOrder SET member_id=%s WHERE order_id=%s", (member_id, order_id))

    def set_item(self, order_id, product_id, quantity, price):
        if not self.execute("UPDATE dbo.SalesOrderItem SET quantity=%s,unit_price=%s WHERE order_id=%s AND product_id=%s",
                            (quantity, price, order_id, product_id)):
            self.execute("INSERT dbo.SalesOrderItem (order_id,product_id,quantity,unit_price) VALUES (%s,%s,%s,%s)",
                         (order_id, product_id, quantity, price))

    def delete_item(self, order_id, product_id):
        return self.execute("DELETE dbo.SalesOrderItem WHERE order_id=%s AND product_id=%s", (order_id, product_id))

    def take_stock(self, product_id, quantity):
        return self.execute("UPDATE dbo.Inventory SET on_hand_qty=on_hand_qty-%s,updated_at=SYSDATETIME() "
                            "WHERE product_id=%s AND on_hand_qty-reserved_qty>=%s", (quantity, product_id, quantity))

    def complete_order(self, order_id):
        self.execute("UPDATE dbo.SalesOrder SET order_status='COMPLETED',order_time=SYSDATETIME() WHERE order_id=%s", (order_id,))

    def cancel_order(self, order_id):
        self.execute("UPDATE dbo.SalesOrder SET order_status='CANCELLED' WHERE order_id=%s", (order_id,))

    def delete_order(self, order_id):
        self.execute("DELETE dbo.SalesOrderItem WHERE order_id=%s", (order_id,))
        self.execute("DELETE dbo.SalesOrder WHERE order_id=%s", (order_id,))
