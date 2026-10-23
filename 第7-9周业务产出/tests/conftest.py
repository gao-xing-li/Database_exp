import json
import os
from pathlib import Path
import sys
from uuid import uuid4
import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app import create_app


@pytest.fixture(scope="session")
def app():
    config = json.loads(Path(os.environ.get("COURSE_CONFIG", ROOT / "config.local.json")).read_text())
    if config["database"] != "AnimeGoodsStoreDB_Week6App":
        pytest.fail("集成测试只允许在专用 Week6App 样例库运行")
    app = create_app(config)
    app.config["TESTING"] = True
    yield app
    for handler in list(app.extensions["audit_logger"].handlers):
        handler.close()
        app.extensions["audit_logger"].removeHandler(handler)


class Client:
    def __init__(self, app, username=None):
        self.client = app.test_client()
        self.token = self.client.get("/api/session").json["data"]["csrf_token"]
        if username:
            response = self.request("POST", "/login", {"username":username,"password":os.environ["COURSE_DEMO_PASSWORD"]})
            assert response.status_code == 200, response.json
            self.token = response.json["data"]["csrf_token"]

    def request(self, method, path, data=None):
        return self.client.open("/api"+path, method=method, json=data, headers={"X-CSRF-Token":self.token})

    def ok(self, method, path, data=None):
        response = self.request(method, path, data)
        assert response.status_code < 300, response.json
        return response.json["data"]


@pytest.fixture
def clients(app):
    return {name:Client(app,name) for name in ["manager","clerk","inventory","customer1","customer2"]}


@pytest.fixture
def business(app, clients):
    """每例生成独立商品/订单；最终用管理受限账户清理自身测试数据。"""
    products,orders = [],[]
    manager,clerk = clients["manager"], clients["clerk"]
    def product(stock=0, reserved=0, price="12.50"):
        value={"product_code":"T"+uuid4().hex[:15],"product_name":"集成测试商品",
               "category_id":1,"ip_id":1,"character_id":1,"sale_price":price,"product_status":"ON_SALE"}
        product_id=manager.ok("POST","/products",value)["product_id"]
        products.append(product_id)
        if stock:
            manager.ok("POST",f"/inventory/{product_id}/adjust",{"delta":stock,"reorder_point":2})
        if reserved:
            with app.extensions["services"].db.transaction("manager") as r:
                r.execute("UPDATE dbo.Inventory SET reserved_qty=%s WHERE product_id=%s",(reserved,product_id))
        return product_id,value
    def order(member_id=1,items=()):
        order_id=clerk.ok("POST","/orders",{"member_id":member_id})["order_id"]
        orders.append(order_id)
        for product_id,quantity in items:
            clerk.ok("PUT",f"/orders/{order_id}/items/{product_id}",{"quantity":quantity})
        return order_id
    def stock(product_id):
        with app.extensions["services"].db.transaction("manager") as r:
            return r.inventory(product_id)
    yield product,order,stock
    with app.extensions["services"].db.transaction("manager") as r:
        for order_id in orders:
            r.delete_order(order_id)
        for product_id in products:
            r.delete_product(product_id)
