"""通过 Flask 入口验证调用合同。驱动替身不执行数据库 SQL。"""
from pathlib import Path
import sys
from unittest.mock import Mock

import pymssql
import pytest

APP = Path(__file__).resolve().parents[2] / "第7-9周业务产出"
sys.path.insert(0, str(APP))
from app import create_app


STOCK = {"product_id": 7, "on_hand_qty": 8, "reserved_qty": 3, "reorder_point": 12, "adjustment_id": 16}


@pytest.fixture
def web(tmp_path, monkeypatch):
    apps = []

    def make(role="inventory", *, inventory_v2=True):
        db = Mock()
        db.cursor.return_value.fetchone.return_value = STOCK
        db.cursor.return_value.fetchall.return_value = [{"product_id": 7, "restock_qty": 7}]
        connect = Mock(return_value=db)
        monkeypatch.setattr(pymssql, "connect", connect)
        app = create_app({
            "server": "127.0.0.1", "port": 1433, "database": "Test",
            "accounts": {role: {"user": "test", "password": "test"}},
            "secret_key": "local test key " * 4,
            "log_file": str(tmp_path / f"{role}-{inventory_v2}.jsonl"),
            "inventory_v2": inventory_v2,
        })
        apps.append(app)
        services = app.extensions["services"]
        user = {"user_id": 1, "username": role, "employee_id": 2, "member_id": 1, "role": role}
        monkeypatch.setattr(services, "current_user", lambda user_id: user if user_id == 1 else None)
        client = app.test_client()
        with client.session_transaction() as session:
            session.update(user_id=1, csrf_token="test-token")
        return client, db, connect, {"X-CSRF-Token": "test-token"}

    yield make
    # 应用的日志文件由测试生成，关闭句柄以便 Windows 清理临时目录。
    for app in apps:
        logger = app.extensions["audit_logger"]
        for handler in list(logger.handlers):
            logger.removeHandler(handler)
            handler.close()


def test_adjustment_uses_sql_entry_and_current_employee(web):
    client, db, connect, headers = web()
    response = client.post("/api/inventory/7/adjust", headers=headers, json={
        "delta": -2, "reorder_point": 12, "reason": " 盘点少了两件 ", "employee_id": 99,
    })
    assert response.status_code == 200
    assert response.json["data"] == STOCK
    assert connect.call_args.kwargs["autocommit"] is True
    sql, params = db.cursor.return_value.execute.call_args.args
    assert "EXEC dbo.AdjustInventory " in sql
    assert params == (7, -2, "盘点少了两件", 2, 12)
    db.commit.assert_not_called()
    db.close.assert_called_once()


def test_change_warning_only(web):
    client, db, connect, headers = web(role="manager")
    response = client.patch("/api/inventory/7/reorder-point", headers=headers, json={"reorder_point": 12})
    assert response.status_code == 200
    assert connect.call_args.kwargs["autocommit"] is True
    sql, params = db.cursor.return_value.execute.call_args.args
    assert "EXEC dbo.SetInventoryReorderPoint " in sql
    assert params == (7, 12)


def test_v2_requires_adjustment_reason(web):
    client, _, connect, headers = web()
    response = client.post("/api/inventory/7/adjust", headers=headers, json={"delta": 5, "reorder_point": 12})
    assert response.status_code == 400
    assert response.json["code"] == "INVALID_INPUT"
    connect.assert_not_called()


@pytest.mark.parametrize(("role", "method", "endpoint"), [
    ("clerk", "POST", "/api/inventory/7/adjust"),
    ("customer", "POST", "/api/inventory/7/adjust"),
    ("clerk", "PATCH", "/api/inventory/7/reorder-point"),
    ("customer", "PATCH", "/api/inventory/7/reorder-point"),
])
def test_adjustment_roles(web, role, method, endpoint):
    client, _, connect, headers = web(role=role)
    response = client.open(endpoint, method=method, json={}, headers=headers)
    assert response.status_code == 403
    connect.assert_not_called()


@pytest.mark.parametrize(("number", "status", "code"), [
    (53101, 404, "NOT_FOUND"), (53102, 400, "INVALID_INPUT"),
    (53104, 409, "BUSINESS_RULE"), (53105, 409, "BUSINESS_RULE"),
])
def test_inventory_sql_error_response(web, number, status, code):
    client, db, _, headers = web()
    db.cursor.return_value.execute.side_effect = [None, pymssql.OperationalError(number, b"SQL error")]
    response = client.post("/api/inventory/7/adjust", headers=headers, json={
        "delta": 5, "reorder_point": 12, "reason": "盘点",
    })
    assert response.status_code == status
    assert response.json["code"] == code
    db.close.assert_called_once()


@pytest.mark.parametrize(("role", "inventory_v2", "shows_suggestion"), [
    ("manager", True, True), ("inventory", True, True),
    ("clerk", True, False), ("customer", True, False), ("inventory", False, False),
])
def test_product_query_version_and_role(web, role, inventory_v2, shows_suggestion):
    client, db, _, _ = web(role=role, inventory_v2=inventory_v2)
    page = client.get("/").get_data(as_text=True)
    assert ('name="reason"' in page) == inventory_v2
    response = client.get("/api/products")
    assert response.status_code == 200
    sql, _ = db.cursor.return_value.execute.call_args.args
    assert ("dbo.RestockQuantity" in sql) == shows_suggestion


def test_v1_can_keep_existing_adjustment_body(web):
    client, db, connect, headers = web(inventory_v2=False)
    response = client.post("/api/inventory/7/adjust", headers=headers, json={"delta": 0, "reorder_point": 12})
    assert response.status_code == 200
    assert connect.call_args.kwargs["autocommit"] is False
    assert any("UPDATE dbo.Inventory" in call.args[0] for call in db.cursor.return_value.execute.call_args_list)
    db.commit.assert_called_once()


def test_v2_checkout_passes_sale_source_during_transition(web):
    client, db, _, headers = web(role="clerk")
    cursor = db.cursor.return_value
    cursor.fetchall.return_value = [{"product_id": 7, "quantity": 2}, {"product_id": 8, "quantity": 1}]
    cursor.fetchone.side_effect = [
        {"order_status": "CREATED", "order_type": "SPOT", "member_id": None},
        {"product_status": "ON_SALE"}, {"product_status": "ON_SALE"},
    ]
    cursor.rowcount = 1
    assert client.post("/api/orders/9/checkout", headers=headers, json={}).status_code == 200
    statements = [call.args for call in cursor.execute.call_args_list]
    audit_context = next(i for i, (sql, *_) in enumerate(statements) if "EXEC dbo.SetInventoryAuditContext 'SALE'" in sql)
    updates = [i for i, (sql, *_) in enumerate(statements) if "UPDATE dbo.Inventory" in sql]
    assert statements[audit_context][1] == (2, 9)
    assert len(updates) == 2 and audit_context < updates[0]
    db.commit.assert_called_once()
