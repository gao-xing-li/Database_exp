# 第1至4周阶段报告

- `main.pdf`：阅读与提交版本。
- `main.tex`：可编辑的 LaTeX 源码。
- `SYSUReport.cls`：从课程提供的模板目录复制，保留原作者与许可证说明。
- `figures/`：模板校徽及从仓库已有 SSMS 截图中裁取的结果区域；没有改写截图中的运行数据。
- `main.log`：最终编译日志；`main.synctex.gz`：源码与 PDF 定位信息。

报告采用“总体介绍＋典型案例”的结构，涵盖业务需求、关系模式、数据库建立与 CRUD、查询与视图、完整性约束、角色权限、小组协作与 AI 辅助下的独立判断、总结及后续工作。完整字段字典、样例元组和 SQL 仍以“第1-4周业务产出”中的各周材料为准。

封面和分工信息取自仓库的《小组分工.md》。报告正文引用已有设计、代码、运行截图和人工审验结论，本次报告生成没有重新执行数据库业务脚本。

## 编辑与编译

在本目录编辑 `main.tex`，与类文件和 `figures/` 一起保存。使用 XeLaTeX 连续编译两次，可更新目录和交叉引用：

```text
xelatex main.tex
xelatex main.tex
```

也可使用已有的 Tectonic：

```text
tectonic --keep-logs --synctex main.tex
```

当前源码使用 Windows 常见字体 SimSun、SimHei、Times New Roman 和 Consolas。其他系统编译时可替换为本机可用字体。

本次内置 LaTeX 编译器返回环境目录错误，已使用本机已有的 Tectonic 完成编译，并将最终 PDF 渲染为页面图片检查图表、分页、字体与代码框。后续编辑请重新编译并检查版面。
