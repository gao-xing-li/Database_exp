class AppError(Exception):
    def __init__(self, code, message, status=400):
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


def require(user, roles):
    if not user:
        raise AppError("AUTH_REQUIRED", "请先登录", 401)
    if user["role"] not in roles:
        raise AppError("FORBIDDEN", "当前账号无权执行此操作", 403)


def integer(value, label, minimum=1, maximum=2147483647):
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise AppError("INVALID_INPUT", f"{label}必须是整数")
    try:
        n = int(value)
    except (ValueError, TypeError):
        raise AppError("INVALID_INPUT", f"{label}必须是整数")
    if not minimum <= n <= maximum:
        raise AppError("INVALID_INPUT", f"{label}超出允许范围")
    return n


def text(value, label, limit):
    if not isinstance(value, str) or not value.strip() or len(value.strip()) > limit:
        raise AppError("INVALID_INPUT", f"请填写有效的{label}（最多{limit}字）")
    return value.strip()
