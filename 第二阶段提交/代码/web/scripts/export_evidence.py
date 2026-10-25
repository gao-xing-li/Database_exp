"""导出无凭据的环境、分层与业务基线证据，不导出认证信息。"""
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from app import create_app


def main():
    app=create_app()
    with app.extensions["services"].db.transaction("manager") as r:
        environment=r.one("SELECT CONVERT(varchar(80),SERVERPROPERTY('ProductVersion')) AS sql_version,"
                          "CONVERT(varchar(80),SERVERPROPERTY('Edition')) AS edition,"
                          "DB_NAME() AS database_name,USER_NAME() AS runtime_user")
        orders=r.all("SELECT order_no,order_status,COUNT(i.product_id) AS item_count,"
                     "SUM(i.quantity*i.unit_price) AS amount FROM dbo.SalesOrder o "
                     "LEFT JOIN dbo.SalesOrderItem i ON i.order_id=o.order_id "
                     "GROUP BY order_no,order_status ORDER BY order_no")
        inventory=r.all("SELECT p.product_code,i.on_hand_qty,i.reserved_qty,"
                        "i.on_hand_qty-i.reserved_qty AS available_qty,i.reorder_point,"
                        "CASE WHEN i.on_hand_qty-i.reserved_qty=0 THEN 'OUT_OF_STOCK' "
                        "WHEN i.on_hand_qty-i.reserved_qty<=i.reorder_point THEN 'LOW_STOCK' "
                        "ELSE 'NORMAL' END AS stock_status FROM dbo.Product p "
                        "JOIN dbo.Inventory i ON i.product_id=p.product_id ORDER BY product_code")
    environment.update({"recorded_at_utc":datetime.now(timezone.utc).isoformat(),
                        "python":sys.version.split()[0],"web":"Flask 3.1.2 / waitress 3.0.2",
                        "driver":"pymssql 2.3.11","sql_business_timezone":"UTC+08:00"})
    (ROOT/"results/environment.json").write_text(json.dumps(environment,ensure_ascii=False,indent=2))
    for name,rows in [("current_order_amounts.csv",orders),("current_inventory.csv",inventory)]:
        with (ROOT/"results"/name).open("w",newline="",encoding="utf-8-sig") as f:
            writer=csv.DictWriter(f,fieldnames=list(rows[0]))
            writer.writeheader();writer.writerows(rows)
    password=os.environ.get("COURSE_DEMO_PASSWORD")
    if password:
        client=app.test_client()
        csrf=client.get("/api/session").json["data"]["csrf_token"]
        samples=[]
        def capture(label,method,path,body=None):
            response=client.open(path,method=method,json=body,headers={"X-CSRF-Token":csrf})
            samples.append({"case":label,"http_status":response.status_code,"response":response.json})
        capture("未登录访问","GET","/api/products")
        capture("错误密码","POST","/api/login",{"username":"manager","password":"wrong-password"})
        login=client.post("/api/login",json={"username":"manager","password":password},headers={"X-CSRF-Token":csrf})
        if login.status_code!=200:raise RuntimeError("导出证据登录失败，请核对 COURSE_DEMO_PASSWORD")
        csrf=login.json["data"]["csrf_token"]
        capture("正常参数化查询","GET","/api/products?q=P001")
        capture("非法价格","POST","/api/products",{"product_code":"EXAMPLE","product_name":"错误示例",
            "category_id":1,"sale_price":"-1","product_status":"ON_SALE"})
        capture("数据库唯一冲突","POST","/api/products",{"product_code":"P001","product_name":"重复编号示例",
            "category_id":1,"sale_price":"1.00","product_status":"ON_SALE"})
        client.post("/api/logout",json={},headers={"X-CSRF-Token":csrf})
        csrf=client.get("/api/session").json["data"]["csrf_token"]
        login=client.post("/api/login",json={"username":"customer1","password":password},headers={"X-CSRF-Token":csrf})
        if login.status_code!=200:raise RuntimeError("顾客样例登录失败")
        csrf=login.json["data"]["csrf_token"]
        capture("顾客越权写入","POST","/api/products",{})
        (ROOT/"results/api_examples.json").write_text(json.dumps(samples,ensure_ascii=False,indent=2))
    print("已导出环境版本、订单金额和库存证据，不包含连接口令或认证表。")


if __name__=="__main__":main()
