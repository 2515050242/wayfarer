# 多文件 CSV 输入诊断

## 2026-11-14 开发记录

参赛者确定十一月的项目增量目标。AI 协助选取复现场景、修改 CLI、编写合成样例和执行回归检查。参赛者的代码审阅和独立复跑待记录。

同一批交接文件可能同时存在列数不齐和引号未闭合的问题。旧版遇到首个坏文件便退出，JSON 模式也只能收到一行文本。修改后，CLI 按契约中的顺序收集每个文件的首个读取或解析错误，并在 JSON 模式下复用现有报告结构。输入有错误时退出码为 `2`，修复输入后再运行目录级契约校验。

```text
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog-malformed --json
```

- 修改前只报告 `courses.csv:2` 的列数错误。
- 修改后同时报告 `courses.csv:2` 的 `csv_row_width` 和 `sessions.csv:2:7` 的 `csv_unterminated_quote`，退出码为 `2`。
- 同一契约的正常样例退出 `0`，字段及跨表引用错误样例报告 5 条诊断并退出 `1`。
- 本地 `moon fmt --check`、`moon check --deny-warn`、`moon test --deny-warn` 通过，86 项测试通过。新增 CI 步骤的断言也已在本地运行。
