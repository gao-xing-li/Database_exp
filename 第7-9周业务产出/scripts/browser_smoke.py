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
    config=json.loads(Path(os.environ.get("COURSE_CONFIG",ROOT/"config.local.json")).read_text())
    if config["database"]!="AnimeGoodsStoreDB_Week6App":
        raise RuntimeError("浏览器测试只允许专用样例库")
    output=ROOT/"results/screenshots"
    output.mkdir(exist_ok=True)
    product_code="B"+uuid4().hex[:12]
    app=create_app(config)
    errors=[]
    with sync_playwright() as p:
        browser=p.chromium.launch()
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
            page.locator("#nav-inventory").click()
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
            page.locator("#nav-orders").click()
            page.locator("#new-order").click()
            page.locator("#new-order-form [name=member_id]").select_option("1")
            page.locator("#new-order-form button[type=submit]").click()
            expect(page.locator("#detail-panel")).to_be_visible()
            with app.extensions["services"].db.transaction("manager") as r:
                product=r.one("SELECT product_id FROM dbo.Product WHERE product_code=%s",(product_code,))
            page.locator("#item-product").select_option(str(product["product_id"]))
            page.locator("#item-qty").fill("2")
            page.locator("[data-action=add-item]").click()
            expect(page.locator("#detail-panel tbody")).to_contain_text("收藏徽章")
            screenshot("05_clerk_draft.png")
            page.locator("[data-action=checkout]").click()
            expect(page.locator("#detail-panel h2")).to_contain_text("已完成")
            expect(page.locator("#detail-panel")).to_contain_text("50.00")
            screenshot("06_clerk_checkout.png")
            logout()
            login("customer1")
            expect(page.locator("#add-product")).to_be_hidden()
            expect(page.locator("#nav-inventory")).to_be_hidden()
            page.locator("#nav-orders").click()
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
            summary={"status":"PASS","flows":["登录/退出","管理员新增修改商品","库存员调整库存","店员草稿明细及结账","顾客本人订单与越权拒绝","390px移动布局"],
                     "console_errors":errors,"screenshots":len(list(output.glob('*.png'))),"checkout_amount":"50.00","remaining_stock":8}
            with app.extensions["services"].db.transaction("manager") as r:
                assert r.inventory(product["product_id"])["on_hand_qty"]==8
            (ROOT/"results/browser.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2))
            print(json.dumps(summary,ensure_ascii=False,indent=2))
        finally:
            browser.close()
            with app.extensions["services"].db.transaction("manager") as r:
                rows=r.all("SELECT product_id FROM dbo.Product WHERE product_code=%s",(product_code,))
                for row in rows:
                    orders=r.all("SELECT order_id FROM dbo.SalesOrderItem WHERE product_id=%s",(row["product_id"],))
                    for order in orders:r.delete_order(order["order_id"])
                    r.delete_product(row["product_id"])


if __name__=="__main__":main()
