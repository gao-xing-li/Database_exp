"""生成可在 SSMS 执行的网页密码重设 SQL，不读取数据库口令或重建数据库。"""
import argparse
from getpass import getpass
from pathlib import Path
import re
from werkzeug.security import generate_password_hash

ROOT = Path(__file__).resolve().parent.parent


def render_reset_sql(username, password):
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,50}", username):
        raise ValueError("账号须为1至50位英文字母、数字、下划线、点或连字符")
    if not 12 <= len(password) <= 200:
        raise ValueError("新密码须为12至200个字符")
    hashed = generate_password_hash(password)
    return f"""-- 在网页实际连接的 SQL Server 实例中，选中应用样例库再执行。
-- 只重设指定网页账号密码，不更改 SQL 登录，不修改业务数据。
-- 本文件仅含加盐哈希，请勿提交本地重设脚本。
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'AnimeGoodsStoreDB_Week6App'
    THROW 51300, N'请先选择 AnimeGoodsStoreDB_Week6App，核对是否为网页实际连接的库。', 1;
IF OBJECT_ID(N'dbo.WebUser', N'U') IS NULL
    THROW 51301, N'尚未初始化 WebUser。请先完成应用数据库初始化。', 1;
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.WebUser SET password_hash=N'{hashed}'
    WHERE username='{username}' AND is_active=1;
    IF @@ROWCOUNT <> 1
        THROW 51302, N'账号不存在或已停用，没有重设密码。', 1;
    COMMIT;
    SELECT username, role, is_active, N'网页密码已重设' AS result
    FROM dbo.WebUser WHERE username='{username}';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;
"""


def write_reset_sql(username, password, output):
    source = render_reset_sql(username, password)
    # BOM 便于 Windows SSMS 正确识别中文，存在时拒绝覆盖。
    with Path(output).open("x", encoding="utf-8-sig", newline="\n") as stream:
        stream.write(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username", default="manager", help="网页账号，默认 manager")
    parser.add_argument("--output", type=Path, default=ROOT / "reset_web_password.local.sql")
    args = parser.parse_args()
    password = getpass("新的网页密码（至少12位，输入不显示）: ")
    if password != getpass("再次输入: "):
        parser.error("两次密码不一致")
    try:
        write_reset_sql(args.username, password, args.output)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print("已生成:", args.output.resolve())
    print("请在 SSMS 连接网页实际使用的实例，选择 AnimeGoodsStoreDB_Week6App，执行该文件。")
    print("执行成功后，用网页账号和刚设置的密码登录。生成文件本身尚未修改数据库。")


if __name__ == "__main__":
    main()
