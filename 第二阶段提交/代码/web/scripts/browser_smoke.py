"""可选的真实浏览器操作验证；先启动 run.py，使用同一 COURSE_DEMO_PASSWORD。
截图只包含课程模拟资料。生成的演示商品/订单最终清理，不改变原样例库存。
"""
import json
import os
from pathlib import Path
import sys
from uuid import uuid4
from playwright.sync_api import sync_playwright, expect

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from app import create_app


def main():
    password=os.environ["COURSE_DEMO_PASSWORD"]
    config=json.loads(Path(os.environ.get("COURSE_CONFIG",ROOT/"config.local.json")).read_text(encoding="utf-8"))
    if config["database"]!="AnimeGoodsStoreDB_Week6App":
        raise RuntimeError("浏览器测试只允许专用样例库")
    output=ROOT/Path(os.environ.get("COURSE_BROWSER_OUTPUT","results/screenshots"))
    output.mkdir(exist_ok=True,parents=True)
    product_code="B"+uuid4().hex[:12]
    app=create_app(config)
    errors=[]
    created_orders=[]
    with sync_playwright() as p:
        browser=p.chromium.launch(channel=os.environ.get("COURSE_BROWSER_CHANNEL") or None)
        page=browser.new_page(viewport={"width":1440,"height":1000},locale="zh-CN")
        page.on("pageerror",lambda e:errors.append(str(e)))
        page.on("dialog",lambda dialog:dialog.accept())
        def screenshot(name):
            page.evaluate("window.scrollTo(0,0)")
            page.screenshot(path=str(output/name),full_page=True)
        def login(username):
            page.goto(os.environ.get("COURSE_BASE_URL","http://127.0.0.1:5000"))
            page.locator("#login-form input[name=username]").fill(username)
            page.locator("#login-form input[name=password]").fill(password)
            page.locator("#login-form button[type=submit]").click()
            expect(page.locator("#workspace")).to_be_visible()
            expect(page.locator("#product-rows tr").first).to_be_visible()
        def logout():
            page.locator("#logout").click()
            expect(page.locator("#login-screen")).to_be_visible()
        try:
            page.goto("http://127.0.0.1:5000")
            screenshot("01_login.png")
            login("manager")
            expect(page.locator("#page-title")).to_have_text("商品管理")
            expect(page.locator("#product-headings th")).to_have_text(["商品","类别 / IP","售价","上架状态","操作"])
            expect(page.locator("[data-action=adjust-stock]")).to_have_count(0)
            page.locator("#nav-inventory").click()
            expect(page.locator("#product-headings th")).to_have_text(["商品","实际库存","预留库存","可售库存","补货警戒值","库存状态","操作"])
            expect(page.locator("#add-product")).to_be_hidden()
            expect(page.locator("[data-action=edit-product]")).to_have_count(0)
            page.locator("#nav-products").click()
            screenshot("02_manager_catalog.png")
            page.locator("#add-product").click()
            form=page.locator("#product-form")
            form.locator("[name=product_code]").fill(product_code)
            form.locator("[name=product_name]").fill("浏览器演示 · 甘雨徽章")
            form.locator("[name=category_id]").select_option("1")
            form.locator("[name=ip_id]").select_option("1")
            form.locator("[name=character_id]").select_option("1")
            form.locator("[name=sale_price]").fill("25.00")
            form.locator("button[type=submit]").click()
            expect(page.locator("#product-dialog")).not_to_be_visible()
            page.locator("#search").fill(product_code)
            page.locator("#search-form button").click()
            expect(page.locator("#product-rows tr")).to_have_count(1)
            expect(page.locator("#product-rows")).to_contain_text("浏览器演示")
            page.locator("[data-action=edit-product]").click()
            form.locator("[name=product_name]").fill("浏览器演示 · 甘雨收藏徽章")
            form.locator("button[type=submit]").click()
            expect(page.locator("#product-dialog")).not_to_be_visible()
            expect(page.locator("#product-rows")).to_contain_text("收藏徽章")
            screenshot("03_manager_product_crud.png")
            logout()
            login("inventory")
            expect(page.locator("#add-product")).to_be_hidden()
            expect(page.locator("#nav-orders")).to_be_hidden()
            expect(page.locator("#nav-products")).to_be_hidden()
            expect(page.locator("nav [data-tab]:visible")).to_have_count(1)
            expect(page.locator("#page-title")).to_have_text("库存管理")
            expect(page.locator("#product-headings")).to_contain_text("实际库存")
            page.reload()
            expect(page.locator("#page-title")).to_have_text("库存管理")
            expect(page.locator("nav [data-tab]:visible")).to_have_count(1)
            page.locator("#search").fill(product_code)
            page.locator("#search-form button").click()
            expect(page.locator("#product-rows tr")).to_have_count(1)
            page.locator("[data-action=adjust-stock]").click()
            page.locator("#inventory-form [name=delta]").fill("10")
            page.locator("#inventory-form [name=reorder_point]").fill("2")
            page.locator("#inventory-form button[type=submit]").click()
            expect(page.locator("#inventory-dialog")).not_to_be_visible()
            expect(page.locator("#metric-stock")).to_have_text("10")
            screenshot("04_inventory_adjustment.png")
            logout()
            login("clerk")
            expect(page.locator("#add-product")).to_be_hidden()
            expect(page.locator("nav [data-tab]:visible")).to_have_count(2)
            expect(page.locator("#nav-inventory")).to_be_hidden()
            expect(page.locator("#product-headings th")).to_have_text(["商品","类别 / IP","售价","可售库存","上架状态"])
            # A catalog filter must not limit the product choices for order entry.
            page.locator("#search").fill("NO_SUCH_"+product_code)
            page.locator("#search-form button").click()
            expect(page.locator("#product-rows")).to_contain_text("没有找到商品")
            page.locator("#nav-orders").click()
            expect(page.locator("#metric-products-label")).to_have_text("订单数量")
            page.locator("#new-order").click()
            page.locator("#new-order-form [name=member_id]").select_option("1")
            with page.expect_response(lambda r:r.url.endswith("/api/orders") and r.request.method=="POST") as created:
                page.locator("#new-order-form button[type=submit]").click()
            created_orders.append(created.value.json()["data"]["order_id"])
            expect(page.locator("#detail-panel")).to_be_visible()
            with app.extensions["services"].db.transaction("manager") as r:
                product=r.one("SELECT product_id FROM dbo.Product WHERE product_code=%s",(product_code,))
            page.locator("#item-product").select_option(str(product["product_id"]))
            page.locator("#item-qty").fill("2")
            page.locator("[data-action=add-item]").click()
            expect(page.locator("#detail-panel tbody")).to_contain_text("收藏徽章")
            screenshot("05_clerk_draft.png")
            # Another manager changes the catalog after this order has been registered.
            admin=app.test_client()
            token=admin.get("/api/session").json["data"]["csrf_token"]
            signed=admin.post("/api/login",json={"username":"manager","password":password},headers={"X-CSRF-Token":token})
            assert signed.status_code==200
            token=signed.json["data"]["csrf_token"]
            changed=admin.put(f"/api/products/{product['product_id']}",json={"product_code":product_code,"product_name":"浏览器演示 · 甘雨收藏徽章","category_id":1,"ip_id":1,"character_id":1,"sale_price":"30.00","product_status":"ON_SALE"},headers={"X-CSRF-Token":token})
            assert changed.status_code==200
            page.locator("[data-action=refresh-orders]").click()
            expect(page.locator("#item-product")).to_contain_text("当前标价¥30.00")
            expect(page.locator("#detail-panel tbody")).to_contain_text("25.00")
            expect(page.locator("#detail-panel .order-summary strong")).to_have_text("¥ 50.00")
            page.locator(".qty-input").fill("3")
            page.locator("[data-action=save-item]").click()
            expect(page.locator("#detail-panel .order-summary strong")).to_have_text("¥ 75.00")
            expect(page.locator("#detail-panel tbody")).to_contain_text("25.00")
            page.locator(".qty-input").fill("2")
            page.locator("[data-action=save-item]").click()
            expect(page.locator("#detail-panel .order-summary strong")).to_have_text("¥ 50.00")
            screenshot("price_lock_before_checkout.png")
            page.locator("[data-action=checkout]").click()
            expect(page.locator("#detail-panel h2")).to_contain_text("已完成")
            expect(page.locator("#detail-panel")).to_contain_text("50.00")
            screenshot("06_clerk_checkout.png")
            logout()
            login("customer1")
            expect(page.locator("#add-product")).to_be_hidden()
            expect(page.locator("#nav-inventory")).to_be_hidden()
            expect(page.locator("#page-metrics")).to_be_hidden()
            expect(page.locator("#product-headings th")).to_have_text(["商品","类别 / IP","售价","可售库存"])
            expect(page.locator("#nav-orders")).to_have_text("我的订单 02")
            page.locator("#nav-orders").click()
            expect(page.locator("#metric-products-label")).to_have_text("我的订单")
            expect(page.locator("#new-order")).to_be_hidden()
            expect(page.locator("#order-rows")).to_contain_text("50.00")
            screenshot("07_customer_own_orders.png")
            page.set_viewport_size({"width":390,"height":844})
            screenshot("08_customer_mobile.png")
            assert page.evaluate("document.documentElement.scrollWidth<=window.innerWidth"),"移动端页面整体溢出"
            # 越权走实际浏览器 fetch，验证友好错误，不依赖隐藏按钮。
            forbidden=page.evaluate("""async()=>{const s=(await(await fetch('/api/session')).json()).data;
              return await(await fetch('/api/products',{method:'POST',headers:{'Content-Type':'application/json',
                'X-CSRF-Token':s.csrf_token},body:'{}'})).json();}""")
            assert forbidden["code"]=="FORBIDDEN"
            assert not errors,errors
            summary={"status":"PASS","flows":["登录/退出","管理员新增修改商品","库存员调整库存","店员草稿明细及结账","目录25元登记后调为30元，刷新和改数量保留25元，结账两件50元","顾客本人订单与越权拒绝","390px移动布局"],
                     "console_errors":errors,"screenshots":len(list(output.glob('*.png'))),"checkout_amount":"50.00","remaining_stock":8,"pricing":{'registered_unit_price': '25.00', 'later_catalog_price': '30.00', 'quantity_three_amount': '75.00', 'quantity_two_checkout_amount': '50.00', 'initial_stock': 10, 'remaining_stock': 8}}
            with app.extensions["services"].db.transaction("manager") as r:
                assert r.inventory(product["product_id"])["on_hand_qty"]==8
            (ROOT/Path(os.environ.get("COURSE_BROWSER_RESULT","results/browser.json"))).write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
            print(json.dumps(summary,ensure_ascii=False,indent=2))
        finally:
            browser.close()
            with app.extensions["services"].db.transaction("manager") as r:
                for order_id in created_orders:r.delete_order(order_id)
                rows=r.all("SELECT product_id FROM dbo.Product WHERE product_code=%s",(product_code,))
                for row in rows:
                    orders=r.all("SELECT order_id FROM dbo.SalesOrderItem WHERE product_id=%s",(row["product_id"],))
                    for order in orders:r.delete_order(order["order_id"])
                    r.delete_product(row["product_id"])


if __name__=="__main__":main()
