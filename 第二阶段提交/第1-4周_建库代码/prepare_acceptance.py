"""生成第5/6周的SSMS执行副本；只读源文件、写本地文件，不连接数据库。"""
import argparse
from pathlib import Path

BASE = Path(__file__).resolve().parent
SUBMISSION = BASE.parent
SCRIPTS = (
    "01_create_tables.sql", "02_insert_sample_data.sql", "03_crud.sql",
    "04_query.sql", "05_view.sql", "06_constraint.sql", "07_role.sql",
)
# 与原表外键依赖顺序一致，复制全部列以保留默认生成的时间值。
TABLES = (
    "ProductCategory", "AnimeIP", "BusinessRole", "Member", "Supplier",
    "CharacterInfo", "Employee", "Product", "Inventory", "PresaleActivity",
    "PresaleReservation", "PurchaseOrder", "PurchaseOrderItem", "SalesOrder",
    "SalesOrderItem",
)


def source(name, database):
    encoding = "gb18030" if int(name[:2]) <= 5 else "utf-8-sig"
    return (BASE / name).read_text(encoding=encoding).replace("AnimeGoodsStoreDB", database)


def create_database(database):
    return (
        "USE master;\nGO\n"
        f"IF DB_ID(N'{database}') IS NOT NULL\n"
        "    THROW 51200, N'验收库已存在，停止。请核对环境，不要继续执行后续文件。', 1;\n"
        "ELSE\n"
        f"    EXEC(N'CREATE DATABASE [{database}]');\nGO\n"
    )


def in_database(database, text):
    return f"USE [{database}];\nGO\n" + text


def build(stage):
    """返回有明确执行顺序的文件内容，生成期间不执行任何SQL。"""
    files = {}
    if stage == "week5":
        database = "AnimeGoodsStoreDB_Week5Review"
        files["00_新建验收库.sql"] = create_database(database)
        files.update({name: source(name, database) for name in SCRIPTS})
        query = SUBMISSION / "第5周_ER模型与业务规则/04_只读验证.sql"
        files["08_第五周只读验证.sql"] = query.read_text(encoding="utf-8-sig").replace(
            "AnimeGoodsStoreDB", database)
    else:
        baseline = "AnimeGoodsStoreDB_Week6Baseline"
        target = "AnimeGoodsStoreDB_Week6Target"
        files["00_新建基线库.sql"] = create_database(baseline)
        files.update({name: source(name, baseline) for name in SCRIPTS})
        files["10_新建目标库.sql"] = create_database(target)
        files["11_目标建表.sql"] = source(SCRIPTS[0], target)
        copy_rows = "SET XACT_ABORT ON;\nBEGIN TRY\n    BEGIN TRAN;\n"
        copy_rows += "".join(
            f"    INSERT dbo.[{table}] SELECT * FROM [{baseline}].dbo.[{table}];\n"
            for table in TABLES)
        copy_rows += (
            "    COMMIT;\nEND TRY\nBEGIN CATCH\n"
            "    IF @@TRANCOUNT > 0 ROLLBACK;\n    THROW;\nEND CATCH;\n")
        files["12_复制全部基线数据.sql"] = in_database(target, copy_rows)
        for number, name in enumerate(SCRIPTS[4:], start=13):
            files[f"{number}_{name[3:]}"] = source(name, target)
        week6 = SUBMISSION / "第6周_函数依赖规范化与迁移"
        files["20_执行第六周迁移.sql"] = in_database(
            target, (week6 / "migration.sql").read_text(encoding="utf-8-sig"))
        files["21_执行第六周回归.sql"] = in_database(
            target, (week6 / "regression.sql").read_text(encoding="utf-8-sig"))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("week5", "week6"))
    args = parser.parse_args()
    files = build(args.stage)
    output = SUBMISSION / "验收准备.local" / args.stage
    # 拒绝覆盖，避免把已有验收工作副本误当成空环境。
    try:
        output.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.exit(2, f"验收执行副本已存在，请核对并使用已有文件，不覆盖：{output}\n")
    for name, text in files.items():
        (output / name).write_text(text, encoding="utf-8-sig")
    print(f"已生成{len(files)}个UTF-8执行副本：{output}")
    print("在SSMS中按文件编号逐个执行；遇到任何非预期错误立即停止，不执行后续文件。")
    print("本工具未连接数据库。原始SQL未改动；原01会重建表，只能用于本次新建的验收库。")


if __name__ == "__main__":
    main()
