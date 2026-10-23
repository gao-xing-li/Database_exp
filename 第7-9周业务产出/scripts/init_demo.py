"""从空环境建立专用课程样例库；存在时立即退出，不清空任何已有库。
管理口令通过 DB_ADMIN_PASSWORD 传入，Web 配置只保存随机受限账户。
"""
import json
import os
from pathlib import Path
import re
import secrets
import sys
import pymssql
from werkzeug.security import generate_password_hash

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
DATABASE = "AnimeGoodsStoreDB_Week6App"


def execute_script(connection, source):
    for batch in re.split(r"^\s*GO\s*(?:--[^\n]*)?$", source, flags=re.M | re.I):
        if not batch.strip():
            continue
        cursor = connection.cursor()
        cursor.execute(batch)
        while cursor.nextset():
            pass


def main():
    password = os.environ.get("DB_ADMIN_PASSWORD")
    if not password:
        sys.exit("请先设置 DB_ADMIN_PASSWORD；此口令只供初始化，不会写入 Web 配置。")
    config_path = Path(os.environ.get("COURSE_CONFIG", ROOT / "config.local.json"))
    if config_path.exists():
        sys.exit("Web 配置已存在，停止；不覆盖账户配置或已有库。")
    demo_password = os.environ.get("COURSE_DEMO_PASSWORD")
    if not demo_password or len(demo_password) < 12:
        sys.exit("请设置至少12位 COURSE_DEMO_PASSWORD，作为本次样例 Web 账号密码。")
    server = os.environ.get("DB_SERVER", "127.0.0.1")
    port = int(os.environ.get("DB_PORT", "14333"))
    connection = pymssql.connect(server=server, port=str(port),
        user=os.environ.get("DB_ADMIN_USER", "sa"), password=password,
        database="master", autocommit=True, charset="UTF-8", as_dict=True)
    try:
        c = connection.cursor()
        c.execute("SELECT DB_ID(%s) AS id", (DATABASE,))
        if c.fetchone()["id"] is not None:
            sys.exit("专用样例库已存在，停止；不会自动重建。请使用现有配置启动。")
        # 固定标识符；不能接受前端、参数或环境变量指定 DROP/CREATE 目标。
        c.execute("CREATE DATABASE AnimeGoodsStoreDB_Week6App")
        c.execute("USE AnimeGoodsStoreDB_Week6App")
        for name in ["01_create_tables.sql", "02_insert_sample_data.sql", "03_crud.sql", "04_query.sql", "05_view.sql", "06_constraint.sql", "07_role.sql"]:
            path = REPO / "第1-4周业务产出" / name
            source = path.read_text(encoding="gb18030" if int(name[:2]) <= 5 else "utf-8-sig")
            execute_script(connection, source.replace("AnimeGoodsStoreDB", DATABASE))
        execute_script(connection, (REPO / "第六周业务产出/migration.sql").read_text(encoding="utf-8-sig"))
        execute_script(connection, (ROOT / "sql/01_web_security.sql").read_text(encoding="utf-8"))
        c = connection.cursor()
        for table, column, sequence in [("Product", "product_id", "WebProductSeq"), ("SalesOrder", "order_id", "WebOrderSeq")]:
            # 全部标识符来自本地常量，数字来自数据库；无用户输入拼接。
            c.execute(f"SELECT COALESCE(MAX({column}),0)+1 AS next_id FROM dbo.{table}")
            start = max(c.fetchone()["next_id"], 10000)
            c.execute(f"CREATE SEQUENCE dbo.{sequence} AS int START WITH {start} INCREMENT BY 1")
        accounts = {}
        for role in ["auth", "manager", "clerk", "inventory", "customer"]:
            username = "course_" + role
            login_password = secrets.token_hex(24) + "aA1!"
            # 随机十六进制和固定标识符，不能由用户提交 SQL 片段。
            c.execute("SELECT name FROM sys.server_principals WHERE name=%s", (username,))
            if c.fetchone():
                sys.exit("同名课程 SQL 登录已存在，停止以避免覆盖。请改用独立 SQL 实例。")
            c.execute(f"CREATE LOGIN [{username}] WITH PASSWORD=N'{login_password}', CHECK_POLICY=ON")
            c.execute(f"CREATE USER [{username}] FOR LOGIN [{username}]")
            c.execute(f"ALTER ROLE [web_{role}] ADD MEMBER [{username}]")
            accounts[role] = {"user": username, "password": login_password}
            if role != "auth":
                for table in ["ProductCategory", "AnimeIP", "CharacterInfo"]:
                    c.execute(f"GRANT SELECT ON dbo.[{table}] TO [web_{role}]")
        c.execute("GRANT UPDATE ON dbo.WebProductSeq TO web_manager")
        c.execute("GRANT UPDATE ON dbo.WebOrderSeq TO web_manager")
        c.execute("GRANT UPDATE ON dbo.WebOrderSeq TO web_clerk")
        for username, role, employee, member in [("manager","manager",3,None), ("clerk","clerk",1,None),
                ("inventory","inventory",2,None), ("customer1","customer",None,1), ("customer2","customer",None,2)]:
            c.execute("INSERT dbo.WebUser(username,password_hash,role,employee_id,member_id) VALUES (%s,%s,%s,%s,%s)",
                      (username, generate_password_hash(demo_password), role, employee, member))
        config = {"server": server, "port": port, "database": DATABASE,
                  "secret_key": secrets.token_hex(32), "cookie_secure": False,
                  "log_file": "results/app.local.jsonl", "accounts": accounts}
        config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
        config_path.chmod(0o600)
        print("已完成原01–07、第六周迁移及Web认证/角色/RLS；独立样例库可启动。")
        print("Web账号：manager、clerk、inventory、customer1、customer2；密码为你设置的 COURSE_DEMO_PASSWORD。")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
