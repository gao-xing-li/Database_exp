from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import json
from pathlib import Path
import pymssql
import pytest
from conftest import Client


def check_error(response, status, code):
    assert response.status_code == status, response.json
    value=response.json
    assert set(value)=={"code","message","data","request_id"}
    assert value["code"]==code
    assert len(value["request_id"])==32
    assert response.headers["X-Request-ID"]==value["request_id"]
    for internal in ["SELECT ","Traceback","pymssql","password_hash","127.0.0.1","/workspace/","DB-Lib"]:
        assert internal not in response.get_data(as_text=True)


def test_login_logout_and_unauthenticated(app):
    client=Client(app)
    check_error(client.request("GET","/products"),401,"AUTH_REQUIRED")
    check_error(client.request("POST","/login",{"username":"clerk","password":"wrong"}),401,"AUTH_FAILED")
    logged=Client(app,"clerk")
    logged.ok("POST","/logout",{})
    check_error(logged.request("GET","/orders"),401,"AUTH_REQUIRED")


def test_password_hash_and_backend_identity(app,clients):
    with app.extensions["services"].db.transaction("auth") as r:
        row=r.user_by_name("clerk")
    assert row["password_hash"].startswith("scrypt:")
    value=clients["clerk"].ok("GET","/session")["user"]
    assert value["employee_id"]==1 and "password_hash" not in value


def test_csrf_and_malformed_json(app,clients):
    response=clients["manager"].client.post("/api/products",json={})
    check_error(response,403,"CSRF_FAILED")
    response=clients["manager"].client.post("/api/products",data="{bad json",content_type="application/json",headers={"X-CSRF-Token":clients["manager"].token})
    check_error(response,400,"INVALID_INPUT")


@pytest.mark.parametrize("username,method,path,data",[
    ("customer1","POST","/products",{}),
    ("customer1","POST","/orders",{}),
    ("clerk","POST","/products",{}),
    ("clerk","POST","/inventory/1/adjust",{"delta":5,"reorder_point":0}),
    ("inventory","GET","/orders",None),
    ("inventory","POST","/products",{}),
])
def test_api_role_denial(clients,username,method,path,data):
    check_error(clients[username].request(method,path,data),403,"FORBIDDEN")


def test_product_crud_and_inventory_initialization(clients,business):
    product,_,stock=business
    pid,value=product()
    assert stock(pid)["on_hand_qty"]==0
    value.update(product_name="修改后的商品",sale_price="23.40",product_status="PENDING")
    clients["manager"].ok("PUT",f"/products/{pid}",value)
    rows=clients["manager"].ok("GET","/products?q="+value["product_code"])
    assert rows[0]["product_name"]=="修改后的商品" and rows[0]["sale_price"]=="23.40"
    assert clients["customer1"].ok("GET","/products?q="+value["product_code"])==[]
    clients["manager"].ok("DELETE",f"/products/{pid}")
    assert stock(pid) is None


def test_product_constraints_and_rollback(clients,business):
    product,_,_=business
    pid,value=product()
    check_error(clients["manager"].request("POST","/products",value),409,"CONSTRAINT_CONFLICT")
    value["ip_id"]=2 # 甘雨不属于星穹铁道
    check_error(clients["manager"].request("PUT",f"/products/{pid}",value),409,"CONSTRAINT_CONFLICT")
    actual=clients["manager"].ok("GET","/products?q="+value["product_code"])[0]
    assert actual["ip_id"]==1


@pytest.mark.parametrize("price",["-1","0","NaN","Infinity","12.345","100000000"])
def test_price_validation(clients,business,price):
    product,_,_=business
    pid,value=product()
    value["sale_price"]=price
    check_error(clients["manager"].request("PUT",f"/products/{pid}",value),400,"INVALID_INPUT")


def test_parameterized_search(clients):
    rows=clients["manager"].ok("GET","/products?q='; DROP TABLE dbo.Product;--")
    assert rows==[]
    assert clients["manager"].ok("GET","/products")


def test_inventory_delta_and_reserved_protection(clients,business):
    product,_,stock=business
    pid,_=product(stock=10,reserved=4)
    clients["inventory"].ok("POST",f"/inventory/{pid}/adjust",{"delta":-6,"reorder_point":3})
    assert stock(pid)["on_hand_qty"]==4 and stock(pid)["reserved_qty"]==4
    check_error(clients["inventory"].request("POST",f"/inventory/{pid}/adjust",{"delta":-1,"reorder_point":3}),409,"BUSINESS_RULE")
    assert stock(pid)["on_hand_qty"]==4


def test_missing_inventory_creation(clients,business,app):
    product,_,stock=business
    pid,_=product()
    with app.extensions["services"].db.transaction("manager") as r:
        r.execute("DELETE dbo.Inventory WHERE product_id=%s",(pid,))
    clients["inventory"].ok("POST",f"/inventory/{pid}/adjust",{"delta":3,"reorder_point":1})
    assert stock(pid)["on_hand_qty"]==3


def test_stocked_product_delete_rejected(clients,business):
    product,_,stock=business
    pid,_=product(stock=3)
    check_error(clients["manager"].request("DELETE",f"/products/{pid}"),409,"BUSINESS_RULE")
    assert stock(pid)["on_hand_qty"]==3


def test_referenced_product_delete_rolls_back_inventory(clients,business):
    product,order,stock=business
    pid,_=product()
    order(items=[(pid,1)])
    check_error(clients["manager"].request("DELETE",f"/products/{pid}"),409,"CONSTRAINT_CONFLICT")
    assert stock(pid) is not None


def test_draft_order_and_item_crud(clients,business):
    product,order,stock=business
    p1,_=product(stock=5);p2,_=product(stock=3)
    oid=order(items=[(p1,2),(p2,1)])
    clients["clerk"].ok("PATCH",f"/orders/{oid}",{"member_id":None})
    clients["clerk"].ok("PUT",f"/orders/{oid}/items/{p1}",{"quantity":3})
    clients["clerk"].ok("DELETE",f"/orders/{oid}/items/{p2}")
    detail=clients["clerk"].ok("GET",f"/orders/{oid}")
    assert detail["order"]["member_id"] is None and detail["items"][0]["quantity"]==3 and len(detail["items"])==1
    assert stock(p1)["on_hand_qty"]==5
    clients["clerk"].ok("DELETE",f"/orders/{oid}")
    check_error(clients["clerk"].request("GET",f"/orders/{oid}"),404,"NOT_FOUND")


def test_checkout_multiple_products_and_historical_price(clients,business):
    product,order,stock=business
    p1,value=product(stock=10,reserved=2);p2,_=product(stock=8,price="20.00")
    oid=order(items=[(p1,3),(p2,2)])
    value["sale_price"]="15.00"
    clients["manager"].ok("PUT",f"/products/{p1}",value)
    clients["clerk"].ok("POST",f"/orders/{oid}/checkout",{})
    detail=clients["clerk"].ok("GET",f"/orders/{oid}")
    assert detail["order"]["order_status"]=="COMPLETED" and detail["order"]["order_time"]
    assert detail["amount"]=="85.00"
    assert stock(p1)["on_hand_qty"]==7 and stock(p1)["reserved_qty"]==2 and stock(p2)["on_hand_qty"]==6
    value["sale_price"]="99.00"
    clients["manager"].ok("PUT",f"/products/{p1}",value)
    assert clients["clerk"].ok("GET",f"/orders/{oid}")["amount"]=="85.00"
    for method,path,data in [("POST",f"/orders/{oid}/checkout",{}),("PATCH",f"/orders/{oid}",{"member_id":2}),
            ("PUT",f"/orders/{oid}/items/{p1}",{"quantity":1}),("DELETE",f"/orders/{oid}",None)]:
        check_error(clients["clerk"].request(method,path,data),409,"BUSINESS_RULE")


def test_insufficient_stock_rolls_back_entire_order(clients,business):
    product,order,stock=business
    p1,value=product(stock=5);p2,_=product(stock=1,reserved=1)
    oid=order(items=[(p1,2),(p2,1)])
    value["sale_price"]="18.00"
    clients["manager"].ok("PUT",f"/products/{p1}",value)
    check_error(clients["clerk"].request("POST",f"/orders/{oid}/checkout",{}),409,"INSUFFICIENT_STOCK")
    detail=clients["clerk"].ok("GET",f"/orders/{oid}")
    assert stock(p1)["on_hand_qty"]==5
    assert detail["order"]["order_status"]=="CREATED" and detail["order"]["order_time"] is None
    assert detail["items"][0]["unit_price"]=="12.50" # 失败时价格同步也回滚


def test_empty_checkout_cancel_and_bad_member(clients,business):
    _,order,_=business
    oid=order()
    check_error(clients["clerk"].request("POST",f"/orders/{oid}/checkout",{}),409,"BUSINESS_RULE")
    check_error(clients["clerk"].request("PATCH",f"/orders/{oid}",{"member_id":2147483647}),409,"BUSINESS_RULE")
    clients["clerk"].ok("POST",f"/orders/{oid}/cancel",{})
    check_error(clients["clerk"].request("DELETE",f"/orders/{oid}"),409,"BUSINESS_RULE")


@pytest.mark.parametrize("quantity",[0,-1,True,1.5,"1.5",1000001])
def test_order_quantity_validation(clients,business,quantity):
    product,order,_=business
    pid,_=product(stock=5);oid=order()
    check_error(clients["clerk"].request("PUT",f"/orders/{oid}/items/{pid}",{"quantity":quantity}),400,"INVALID_INPUT")


def test_customer_isolation_api_and_sql_rls(clients,business,app):
    product,order,_=business
    pid,_=product();mine=order(1,[(pid,1)]);other=order(2,[(pid,1)])
    rows=clients["customer1"].ok("GET","/orders")
    assert mine in [r["order_id"] for r in rows] and other not in [r["order_id"] for r in rows]
    check_error(clients["customer1"].request("GET",f"/orders/{other}"),404,"NOT_FOUND")
    with app.extensions["services"].db.transaction("customer",1) as r:
        assert r.order(other) is None and r.items(other)==[]
        assert r.order(mine) is not None
    with app.extensions["services"].db.transaction("customer",None) as r:
        assert r.order(mine) is None
    with pytest.raises(pymssql.Error):
        with app.extensions["services"].db.transaction("customer",1) as r:
            r.execute("EXEC sys.sp_set_session_context @key=N'member_id',@value=2")


@pytest.mark.parametrize("role,sql",[
    ("customer","UPDATE dbo.Inventory SET on_hand_qty=on_hand_qty WHERE product_id=1"),
    ("clerk","UPDATE dbo.Product SET sale_price=sale_price WHERE product_id=1"),
    ("inventory","SELECT * FROM dbo.Member"),
    ("auth","SELECT * FROM dbo.SalesOrder"),
])
def test_restricted_database_accounts(app,role,sql):
    with pytest.raises(pymssql.Error) as error:
        with app.extensions["services"].db.transaction(role,1) as r:
            r.execute(sql)
    assert error.value.args[0]==229


def test_concurrent_checkout_no_oversell(clients,business,app):
    product,order,stock=business
    pid,_=product(stock=3,reserved=1)
    o1=order(items=[(pid,2)]);o2=order(items=[(pid,2)])
    c1,c2=Client(app,"clerk"),Client(app,"clerk")
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(c.request,"POST",f"/orders/{o}/checkout",{}) for c,o in [(c1,o1),(c2,o2)]]
        responses=[f.result() for f in futures]
    assert sorted(r.status_code for r in responses)==[200,409]
    assert stock(pid)["on_hand_qty"]==1 and stock(pid)["reserved_qty"]==1
    assert {r.json["code"] for r in responses}=={"OK","INSUFFICIENT_STOCK"}


def test_database_connection_failure_and_log(app,clients):
    config=app.extensions["services"].db.config
    original=config["port"]
    try:
        config["port"]=1
        response=clients["clerk"].request("GET","/products")
        check_error(response,503,"DATABASE_UNAVAILABLE")
    finally:
        config["port"]=original
    logger=app.extensions["audit_logger"]
    for h in logger.handlers:h.flush()
    lines=Path(logger.handlers[0].baseFilename).read_text().splitlines()
    records=[]
    for line in lines:
        try: records.append(json.loads(line))
        except json.JSONDecodeError: pass # 后端异常栈只用于定位，不展示给前端
    audit=[r for r in records if r.get("request_id")==response.json["request_id"] and "result" in r][-1]
    assert audit["error_code"]=="DATABASE_UNAVAILABLE" and audit["result"]=="failure"
    assert all(k in audit for k in ["time","operation","role","request_id"])


def test_html_security_headers(app):
    response=app.test_client().get("/")
    assert response.status_code==200
    assert "frame-ancestors 'none'" in response.headers["Content-Security-Policy"]
    assert response.headers["X-Content-Type-Options"]=="nosniff"
