"""为第10—13周建立独立 v1.0 副本并安装第三阶段对象。"""
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
APP = ROOT.parent / "第7-9周业务产出"
DATABASE = "AnimeGoodsStoreDB_Week6App_Stage3"
LOGIN_PREFIX = "course_stage3_"
SCRIPTS = (
    "inventory_schema.sql",
    "procedure.sql",
    "function.sql",
    "trigger.sql",
    "restock_transaction.sql",
    "recursive_query.sql",
)

sys.path.insert(0, str(APP))
from scripts import init_demo


def main():
    config_path = Path(os.environ.get("COURSE_CONFIG", ROOT / "config.local.json"))
    init_demo.initialize(
        DATABASE, LOGIN_PREFIX, config_path,
        extra_scripts=tuple(ROOT / "代码" / name for name in SCRIPTS),
        config_fields={"inventory_v2": True, "log_file": str(ROOT / "结果/app.local.jsonl")},
    )


if __name__ == "__main__":
    main()
