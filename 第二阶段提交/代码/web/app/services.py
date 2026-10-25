"""业务层：身份、角色、状态和事务范围；本模块不编写 SQL。"""
from decimal import Decimal, InvalidOperation
from werkzeug.security import check_password_hash, generate_password_hash
from .errors import AppError, require, integer, text

DUMMY_HASH = generate_password_hash("unmatchable-dummy-password")
STAFF = {"manager", "clerk", "inventory"}
SALES = {"manager", "clerk"}
ALL = STAFF | {"customer"}


class Services:
    def __init__(self, db):
        self.db = db

    def principal(self, row, repo):
        if not row or not row["is_active"]:
            return None
        if row["role"] == "customer":
            member = repo.member(row["member_id"])
            if not member or member["member_status"] != "ACTIVE":
                return None
        else:
            employee = repo.employee(row["employee_id"])
            names = {"manager": "店长/管理员", "clerk": "销售/收银店员", "inventory": "库存管理员"}
            if not employee or employee["employee_status"] != "ACTIVE" or employee["role_name"] != names.get(row["role"]):
                return None
        return {k: row[k] for k in ("user_id", "username", "role", "employee_id", "member_id")}

    def login(self, data):
        username = text(data.get("username"), "账号", 50)
        password = data.get("password")
        if not isinstance(password, str) or not 1 <= len(password) <= 200:
            raise AppError("INVALID_INPUT", "请填写密码")
        with self.db.transaction("auth") as repo:
            row = repo.user_by_name(username)
            matched = check_password_hash(row["password_hash"] if row else DUMMY_HASH, password)
            user = self.principal(row, repo) if matched else None
            if not user:
                raise AppError("AUTH_FAILED", "账号或密码不正确，或账号已停用", 401)
            return user

    def current_user(self, user_id):
        if user_id is None:
            return None
        with self.db.transaction("auth") as repo:
            return self.principal(repo.user_by_id(user_id), repo)

    def connection(self, user):
        return self.db.transaction(user["role"], user.get("member_id"))

    def lookups(self, user):
        require(user, ALL)
        with self.connection(user) as repo:
            return repo.lookups(user["role"] in SALES)

    def products(self, user, term):
        require(user, ALL)
        if len(term) > 100:
            raise AppError("INVALID_INPUT", "搜索内容最多100字")
        with self.connection(user) as repo:
            return repo.products("%" + term + "%", user["role"] in STAFF)

    def product_values(self, data):
        code = text(data.get("product_code"), "商品编号", 20)
        if not code.isascii():
            raise AppError("INVALID_INPUT", "商品编号请使用英文、数字或符号")
        name = text(data.get("product_name"), "商品名称", 150)
        category = integer(data.get("category_id"), "类别")
        ip_id = integer(data["ip_id"], "IP") if data.get("ip_id") not in (None, "") else None
        character_id = integer(data["character_id"], "角色") if data.get("character_id") not in (None, "") else None
        if character_id and not ip_id:
            raise AppError("INVALID_INPUT", "指定角色时必须选择所属IP")
        try:
            price = Decimal(str(data.get("sale_price")))
            if not price.is_finite() or not Decimal("0.01") <= price <= Decimal("99999999.99") or price != price.quantize(Decimal("0.01")):
                raise InvalidOperation
        except (InvalidOperation, ValueError):
            raise AppError("INVALID_INPUT", "价格必须为正数且最多两位小数")
        status = data.get("product_status")
        if status not in {"ON_SALE", "PENDING", "STOPPED"}:
            raise AppError("INVALID_INPUT", "请选择有效商品状态")
        return code, name, category, ip_id, character_id, price, status

    def save_product(self, user, data, product_id=None):
        require(user, {"manager"})
        values = self.product_values(data)
        with self.connection(user) as repo:
            if product_id is None:
                product_id = repo.create_product(values)
            elif not repo.update_product(product_id, values):
                raise AppError("NOT_FOUND", "商品不存在", 404)
            return {"product_id": product_id}

    def delete_product(self, user, product_id):
        require(user, {"manager"})
        with self.connection(user) as repo:
            if not repo.product(product_id, lock=True):
                raise AppError("NOT_FOUND", "商品不存在", 404)
            inventory = repo.inventory(product_id)
            if inventory and (inventory["on_hand_qty"] or inventory["reserved_qty"]):
                raise AppError("BUSINESS_RULE", "仍有库存，请使用停售保存商品资料", 409)
            repo.delete_product(product_id)
            return {}

    def adjust_inventory(self, user, product_id, data):
        require(user, {"manager", "inventory"})
        delta = integer(data.get("delta"), "调整数量", -1000000, 1000000)
        reorder = integer(data.get("reorder_point"), "补货警戒值", 0, 1000000)
        with self.connection(user) as repo:
            if not repo.product(product_id, lock=True):
                raise AppError("NOT_FOUND", "商品不存在", 404)
            stock = repo.inventory(product_id)
            if stock is None:
                repo.init_inventory(product_id)
                stock = {"on_hand_qty": 0, "reserved_qty": 0}
            new_qty = stock["on_hand_qty"] + delta
            if new_qty < stock["reserved_qty"] or new_qty > 2147483647:
                raise AppError("BUSINESS_RULE", "调整后库存不能少于预留库存或超出范围", 409)
            repo.adjust_inventory(product_id, delta, reorder)
            return repo.inventory(product_id)

    def orders(self, user):
        require(user, SALES | {"customer"})
        with self.connection(user) as repo:
            return repo.orders(user["member_id"] if user["role"] == "customer" else None)

    def accessible_order(self, repo, user, order_id, lock=False):
        order = repo.order(order_id, lock)
        if not order or (user["role"] == "customer" and order["member_id"] != user["member_id"]):
            raise AppError("NOT_FOUND", "订单不存在", 404)
        return order

    def draft(self, repo, user, order_id):
        order = self.accessible_order(repo, user, order_id, lock=True)
        if order["order_status"] != "CREATED" or order["order_type"] != "SPOT":
            raise AppError("BUSINESS_RULE", "仅现货草稿订单可以执行此操作", 409)
        return order

    def order_detail(self, user, order_id):
        require(user, SALES | {"customer"})
        with self.connection(user) as repo:
            order = self.accessible_order(repo, user, order_id)
            items = repo.items(order_id)
            return {"order": order, "items": items, "amount": sum((i["amount"] for i in items), Decimal(0))}

    def member_id(self, repo, data):
        member_id = data.get("member_id")
        if member_id in (None, ""):
            return None
        member_id = integer(member_id, "会员")
        member = repo.member(member_id)
        if not member or member["member_status"] != "ACTIVE":
            raise AppError("BUSINESS_RULE", "请选择有效会员，散客可留空", 409)
        return member_id

    def create_order(self, user, data):
        require(user, SALES)
        with self.connection(user) as repo:
            member_id = self.member_id(repo, data)
            return {"order_id": repo.create_order(member_id, user["employee_id"])}

    def update_order(self, user, order_id, data):
        require(user, SALES)
        with self.connection(user) as repo:
            self.draft(repo, user, order_id)
            repo.update_order(order_id, self.member_id(repo, data))
            return {}

    def set_item(self, user, order_id, product_id, data):
        require(user, SALES)
        qty = integer(data.get("quantity"), "购买数量", 1, 1000000)
        with self.connection(user) as repo:
            self.draft(repo, user, order_id)
            product = repo.product(product_id, lock=True)
            if not product or product["product_status"] != "ON_SALE":
                raise AppError("BUSINESS_RULE", "商品不存在或未上架", 409)
            existing = repo.item(order_id, product_id)
            if existing:
                price = existing["unit_price"]
            else:
                try:
                    expected = Decimal(str(data.get("expected_unit_price")))
                    if not expected.is_finite() or not Decimal("0.01") <= expected <= Decimal("99999999.99") or expected != expected.quantize(Decimal("0.01")):
                        raise InvalidOperation
                except (InvalidOperation, ValueError):
                    raise AppError("INVALID_INPUT", "请先刷新商品目录并选择商品标价")
                if expected != product["sale_price"]:
                    raise AppError("PRICE_CHANGED", "商品标价已更新，请刷新目录并核对后重新登记", 409)
                price = product["sale_price"]
            # 订单锁串行化明细操作，已有行修改数量时始终保留登记单价。
            repo.set_item(order_id, product_id, qty, price)
            return {}

    def delete_item(self, user, order_id, product_id):
        require(user, SALES)
        with self.connection(user) as repo:
            self.draft(repo, user, order_id)
            if not repo.delete_item(order_id, product_id):
                raise AppError("NOT_FOUND", "订单明细不存在", 404)
            return {}

    def checkout(self, user, order_id):
        require(user, SALES)
        with self.connection(user) as repo:
            order = self.draft(repo, user, order_id)
            if order["member_id"]:
                self.member_id(repo, order)
            items = repo.items(order_id)
            if not items:
                raise AppError("BUSINESS_RULE", "请先添加商品明细", 409)
            # 固定 product_id 顺序；与商品维护/库存调整采用相同锁顺序。
            for item in items:
                product = repo.product(item["product_id"], lock=True)
                if not product or product["product_status"] != "ON_SALE":
                    raise AppError("BUSINESS_RULE", "订单内有商品已停售，请调整草稿", 409)
                if repo.take_stock(item["product_id"], item["quantity"]) != 1:
                    raise AppError("INSUFFICIENT_STOCK", "可售库存不足，订单未结账，请调整数量", 409)
            repo.complete_order(order_id)
            return {"order_id": order_id}

    def cancel_order(self, user, order_id):
        require(user, SALES)
        with self.connection(user) as repo:
            self.draft(repo, user, order_id)
            repo.cancel_order(order_id)
            return {}

    def delete_order(self, user, order_id):
        require(user, SALES)
        with self.connection(user) as repo:
            self.draft(repo, user, order_id)
            repo.delete_order(order_id)
            return {}
