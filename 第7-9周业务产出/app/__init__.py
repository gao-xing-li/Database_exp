import json
import logging
import os
import traceback
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from uuid import uuid4
import pymssql
from flask import Flask, g, jsonify, render_template, request, session
from flask.json.provider import DefaultJSONProvider
from werkzeug.exceptions import HTTPException
from .db import Database
from .services import Services
from .errors import AppError

ROOT = Path(__file__).resolve().parent.parent


class JSONProvider(DefaultJSONProvider):
    @staticmethod
    def default(obj):
        if isinstance(obj, Decimal):
            return str(obj)
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()
        return DefaultJSONProvider.default(obj)


def create_app(config=None):
    if config is None:
        config = json.loads(Path(os.environ.get("COURSE_CONFIG", ROOT / "config.local.json")).read_text(encoding="utf-8"))
    if len(config["secret_key"]) < 32 or config["secret_key"].startswith("REPLACE"):
        raise ValueError("配置独立随机 secret_key 后再启动")
    app = Flask(__name__)
    app.json = JSONProvider(app)
    app.config.update(SECRET_KEY=config["secret_key"], MAX_CONTENT_LENGTH=16384,
                      SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Strict",
                      SESSION_COOKIE_SECURE=config.get("cookie_secure", False))
    from datetime import timedelta
    app.config["PERMANENT_SESSION_LIFETIME"] = timedelta(hours=2)
    service = Services(Database(config))
    app.extensions["services"] = service
    logger = logging.getLogger("course." + uuid4().hex)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    logfile = Path(config.get("log_file", ROOT / "results/app.local.jsonl"))
    if not logfile.is_absolute():
        logfile = ROOT / logfile
    logfile.parent.mkdir(parents=True, exist_ok=True)
    handler = logging.FileHandler(logfile, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    app.extensions["audit_logger"] = logger

    def result(data=None, code="OK", message="操作成功", status=200):
        g.result_code = code
        return jsonify(code=code, message=message, data=data, request_id=g.request_id), status

    @app.before_request
    def prepare():
        g.request_id, g.user, g.result_code = uuid4().hex, None, "OK"
        session.setdefault("csrf_token", uuid4().hex)
        if request.path.startswith("/api/"):
            if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
                import hmac
                if not hmac.compare_digest(request.headers.get("X-CSRF-Token", ""), session["csrf_token"]):
                    raise AppError("CSRF_FAILED", "页面已过期，请刷新后重试", 403)
            if request.path not in {"/api/login", "/api/session"}:
                g.user = service.current_user(session.get("user_id"))
                if not g.user:
                    session.pop("user_id", None)
                    raise AppError("AUTH_REQUIRED", "请先登录", 401)

    @app.after_request
    def audit(response):
        response.headers.update({"X-Request-ID": g.get("request_id", ""), "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"})
        if request.path.startswith("/api/"):
            logger.info(json.dumps({"time": datetime.now(timezone.utc).isoformat(),
                "request_id": g.get("request_id"), "operation": request.endpoint or "unknown",
                "role": (g.get("user") or {}).get("role", session.get("audit_role", "anonymous")),
                "error_code": g.get("result_code", "INTERNAL_ERROR"),
                "result": "success" if response.status_code < 400 else "failure",
                "http_status": response.status_code}, ensure_ascii=False))
        return response

    @app.errorhandler(Exception)
    def handle_error(error):
        if isinstance(error, AppError):
            return result(code=error.code, message=error.message, status=error.status)
        if isinstance(error, HTTPException):
            return result(code="INVALID_INPUT" if error.code == 400 else "HTTP_ERROR",
                          message="请求格式有误或地址不可用", status=error.code)
        logger.error(json.dumps({"time": datetime.now(timezone.utc).isoformat(), "request_id": g.get("request_id"),
                     "operation": request.endpoint, "error_type": type(error).__name__,
                     "traceback": traceback.format_exc()}, ensure_ascii=False))
        if isinstance(error, pymssql.IntegrityError):
            return result(code="CONSTRAINT_CONFLICT", message="数据冲突，请检查编号、关联资料或历史记录", status=409)
        if isinstance(error, pymssql.Error):
            number = error.args[0] if error.args else None
            if number in (1205, 1222):
                return result(code="TRANSACTION_FAILED", message="操作发生冲突，请刷新后重试", status=409)
            return result(code="DATABASE_UNAVAILABLE", message="系统暂时无法完成操作，请稍后重试", status=503)
        return result(code="INTERNAL_ERROR", message="系统暂时无法完成操作，请凭请求编号联系维护人员", status=500)

    def data():
        value = request.get_json()
        if not isinstance(value, dict):
            raise AppError("INVALID_INPUT", "请提交有效的表单内容")
        return value

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/api/session")
    def get_session():
        g.user = service.current_user(session.get("user_id"))
        return result({"user": g.user, "csrf_token": session["csrf_token"]})

    @app.post("/api/login")
    def login():
        g.user = service.login(data())
        session.clear()
        session.update(user_id=g.user["user_id"], audit_role=g.user["role"], csrf_token=uuid4().hex)
        session.permanent = True
        return result({"user": g.user, "csrf_token": session["csrf_token"]})

    @app.post("/api/logout")
    def logout():
        session.clear()
        return result({})

    @app.get("/api/lookups")
    def lookups():
        return result(service.lookups(g.user))

    @app.get("/api/products")
    def products():
        return result(service.products(g.user, request.args.get("q", "")))

    @app.post("/api/products")
    def create_product():
        return result(service.save_product(g.user, data()), status=201)

    @app.put("/api/products/<int:product_id>")
    def update_product(product_id):
        return result(service.save_product(g.user, data(), product_id))

    @app.delete("/api/products/<int:product_id>")
    def delete_product(product_id):
        return result(service.delete_product(g.user, product_id))

    @app.post("/api/inventory/<int:product_id>/adjust")
    def adjust_inventory(product_id):
        return result(service.adjust_inventory(g.user, product_id, data()))

    @app.route("/api/orders", methods=["GET", "POST"])
    def orders():
        return result(service.orders(g.user)) if request.method == "GET" else result(service.create_order(g.user, data()), status=201)

    @app.route("/api/orders/<int:order_id>", methods=["GET", "PATCH", "DELETE"])
    def order(order_id):
        if request.method == "GET":
            return result(service.order_detail(g.user, order_id))
        if request.method == "PATCH":
            return result(service.update_order(g.user, order_id, data()))
        return result(service.delete_order(g.user, order_id))

    @app.route("/api/orders/<int:order_id>/items/<int:product_id>", methods=["PUT", "DELETE"])
    def order_item(order_id, product_id):
        if request.method == "PUT":
            return result(service.set_item(g.user, order_id, product_id, data()))
        return result(service.delete_item(g.user, order_id, product_id))

    @app.post("/api/orders/<int:order_id>/checkout")
    def checkout(order_id):
        return result(service.checkout(g.user, order_id))

    @app.post("/api/orders/<int:order_id>/cancel")
    def cancel(order_id):
        return result(service.cancel_order(g.user, order_id))

    return app
