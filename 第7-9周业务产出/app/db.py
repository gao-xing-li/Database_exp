"""数据访问层：只有本模块和 repository.py 在运行时接触 SQL Server。"""
from contextlib import contextmanager
import pymssql
from .repository import Repository


class Database:
    def __init__(self, config):
        self.config = config

    @contextmanager
    def transaction(self, role, member_id=None):
        account = self.config["accounts"][role]
        connection = pymssql.connect(
            server=self.config["server"], port=str(self.config["port"]),
            database=self.config["database"], user=account["user"],
            password=account["password"], charset="UTF-8", as_dict=True,
            login_timeout=5, timeout=10, tds_version="7.4",
        )
        try:
            cursor = connection.cursor()
            cursor.execute("SET XACT_ABORT ON; SET ANSI_NULLS ON; SET ANSI_PADDING ON; "
                           "SET ANSI_WARNINGS ON; SET ARITHABORT ON; "
                           "SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; "
                           "SET NUMERIC_ROUNDABORT OFF;")
            if role == "customer":
                cursor.execute("EXEC sys.sp_set_session_context @key=N'member_id', "
                               "@value=%s, @read_only=1", (member_id,))
            yield Repository(cursor)
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()
