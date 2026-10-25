import re
import pytest
from werkzeug.security import check_password_hash
from scripts.reset_web_password import render_reset_sql, write_reset_sql


def test_reset_hash_matches_without_plaintext():
    password = "Local-test-only-2026!"
    source = render_reset_sql("manager", password)
    hashed = re.search(r"SET password_hash=N'([^']+)'", source).group(1)
    assert check_password_hash(hashed, password)
    assert password not in source
    assert "WHERE username='manager' AND is_active=1" in source
    assert "DB_NAME() <> N'AnimeGoodsStoreDB_Week6App'" in source
    assert "IF @@ROWCOUNT <> 1" in source
    assert "BEGIN TRAN" in source and "ROLLBACK" in source
    assert "CREATE " not in source and "DELETE " not in source


@pytest.mark.parametrize("username,password", [
    ("manager'; DROP TABLE dbo.WebUser;--", "Local-test-only-2026!"),
    ("", "Local-test-only-2026!"),
    ("manager", "short"),
    ("manager", "x" * 201),
])
def test_invalid_reset_input_rejected(username, password):
    with pytest.raises(ValueError):
        render_reset_sql(username, password)


def test_reset_output_preserves_existing_file(tmp_path):
    output = tmp_path / "reset.local.sql"
    write_reset_sql("manager", "Local-test-only-2026!", output)
    original = output.read_bytes()
    assert original.startswith(b"\xef\xbb\xbf")
    with pytest.raises(FileExistsError):
        write_reset_sql("manager", "Another-test-only-2026!", output)
    assert output.read_bytes() == original
