"""从空环境建立专用课程样例库；存在时立即退出，不清空任何已有库。
管理口令通过 DB_ADMIN_PASSWORD 传入；Windows 本机可设 DB_ADMIN_TRUSTED=1。
Web 配置只保存随机受限账户，运行时连接方式不变。
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
DATABASE = "AnimeGoodsStoreDB_Week6App"
BASE_SCRIPTS = (
    "01_create_tables.sql", "02_insert_sample_data.sql", "03_crud.sql",
    "04_query.sql", "05_view.sql", "06_constraint.sql", "07_role.sql",
)


def resolve_sources():
    """兼容开发目录与按阶段组织的提交目录，在连接数据库前核对全部依赖。"""
    candidates = [
        (ROOT.parent / "第1-4周业务产出", ROOT.parent / "第六周业务产出/migration.sql"),
        (ROOT.parents[2] / "第1-4周_建库代码",
         ROOT.parents[2] / "第6周_函数依赖规范化与迁移/migration.sql"),
    ]
    for base, migration in candidates:
        if all((base / name).is_file() for name in BASE_SCRIPTS) and migration.is_file():
            return base, migration
    raise FileNotFoundError("缺少基础01—07或第六周migration.sql，请保留提交目录的同级阶段结构。")


def execute_script(connection, source):
    for batch in re.split(r"^\s*GO\s*(?:--[^\n]*)?$", source, flags=re.M | re.I):
        if not batch.strip():
            continue
        cursor = connection.cursor()
        cursor.execute(batch)
        while cursor.nextset():
            pass


def fetch_dict(cursor):
    """兼容 pymssql 字典行和 pyodbc 行；仅供初始化使用。"""
    row = cursor.fetchone()
    if row is None or isinstance(row, dict):
        return row
    return dict(zip((column[0] for column in cursor.description), row))


def connect_admin(server, port, trusted=False, password=None):
    if trusted:
        if os.name != "nt" or server not in {"127.0.0.1", "localhost", "."}:
            raise ValueError("Windows 身份初始化仅支持本机 SQL Server。")
        import pyodbc
        # 本机课程实例使用自签名证书，行为与 sqlcmd -E -C 一致。
        return pyodbc.connect(
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER=tcp:{server},{port};DATABASE=master;"
            "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
            autocommit=True, timeout=5)
    return pymssql.connect(server=server, port=str(port),
        user=os.environ.get("DB_ADMIN_USER", "sa"), password=password,
        database="master", autocommit=True, charset="UTF-8", as_dict=True)


def main():
    base, migration = resolve_sources()
    trusted = os.environ.get("DB_ADMIN_TRUSTED") == "1"
    password = os.environ.get("DB_ADMIN_PASSWORD")
    if not trusted and not password:
        sys.exit("请先设置 DB_ADMIN_PASSWORD；此口令只供初始化，不会写入 Web 配置。")
    config_path = Path(os.environ.get("COURSE_CONFIG", ROOT / "config.local.json"))
    if config_path.exists():
        sys.exit("Web 配置已存在，停止；不覆盖账户配置或已有库。")
    demo_password = os.environ.get("COURSE_DEMO_PASSWORD")
    # 用户指定的本机演示短密码需要显式开启；默认要求仍为至少12位。
    minimum = 1 if trusted and os.environ.get("COURSE_DEMO_ALLOW_SHORT_PASSWORD") == "1" else 12
    if not demo_password or not minimum <= len(demo_password) <= 200:
        sys.exit(f"请设置 {minimum} 至200位 COURSE_DEMO_PASSWORD，作为本次样例 Web 账号密码。")
    server = os.environ.get("DB_SERVER", "127.0.0.1")
    port = int(os.environ.get("DB_PORT", "14333"))
    parameter = "?" if trusted else "%s"
    connection = connect_admin(server, port, trusted, password)
    try:
        c = connection.cursor()
        c.execute(f"SELECT DB_ID({parameter}) AS id", (DATABASE,))
        if fetch_dict(c)["id"] is not None:
            sys.exit("专用样例库已存在，停止；不会自动重建。请使用现有配置启动。")
        # 固定标识符；不能接受前端、参数或环境变量指定 DROP/CREATE 目标。
        c.execute("CREATE DATABASE AnimeGoodsStoreDB_Week6App")
        c.execute("USE AnimeGoodsStoreDB_Week6App")
        for name in BASE_SCRIPTS:
            path = base / name
            source = path.read_text(encoding="gb18030" if int(name[:2]) <= 5 else "utf-8-sig")
            execute_script(connection, source.replace("AnimeGoodsStoreDB", DATABASE))
        execute_script(connection, migration.read_text(encoding="utf-8-sig"))
        execute_script(connection, (ROOT / "sql/01_web_security.sql").read_text(encoding="utf-8"))
        c = connection.cursor()
        for table, column, sequence in [("Product", "product_id", "WebProductSeq"), ("SalesOrder", "order_id", "WebOrderSeq")]:
            # 全部标识符来自本地常量，数字来自数据库；无用户输入拼接。
            c.execute(f"SELECT COALESCE(MAX({column}),0)+1 AS next_id FROM dbo.{table}")
            start = max(fetch_dict(c)["next_id"], 10000)
            c.execute(f"CREATE SEQUENCE dbo.{sequence} AS int START WITH {start} INCREMENT BY 1")
        accounts = {}
        for role in ["auth", "manager", "clerk", "inventory", "customer"]:
            username = "course_" + role
            login_password = secrets.token_hex(24) + "aA1!"
            # 随机十六进制和固定标识符，不能由用户提交 SQL 片段。
            c.execute(f"SELECT name FROM sys.server_principals WHERE name={parameter}", (username,))
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
            # 占位符来自驱动选择，用户值始终通过参数绑定。
            c.execute("INSERT dbo.WebUser(username,password_hash,role,employee_id,member_id) VALUES ("
                      + ",".join([parameter] * 5) + ")",
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
