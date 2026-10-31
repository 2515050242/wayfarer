# 生态定位核对（2026-10-30）

本文件记录 Wayfarer 与 Mooncakes 公开索引中相邻工具的职责对照，核对时间为 2026-10-30。若各项目后续扩展职责，以各项目当时的自述为准。

| 项目 | 版本 | 输入单位 | 定位 | 与 Wayfarer 的关系 |
| --- | --- | --- | --- | --- |
| [moon-csv-lite](https://mooncakes.io/docs/clhhhhh/moon-csv-lite) | 0.1.0 | 单个 CSV 表 | 方言检测、schema 推断、列画像、缺失统计与单表质量契约 | 覆盖 Wayfarer 的单表画像与推断场景；不做跨表引用，不做多文件数据集 |
| [moonverity](https://mooncakes.io/docs/Wchwch777/moonverity) | 0.1.2 | 单个 CSV/JSONL 数据集 | 逐文件数据契约、质量门禁、质量评分、契约 diff 与 CI 退出码 | 覆盖 JSONL 与质量评分；行级规范化后不保留物理行号，不做跨文件引用 |
| wayfarer（本项目） | 未发布 | 一个目录内的多个相关 CSV 表 | 必需表/表头、最小行数、非空列、单/多列唯一键、跨文件引用、字段级规则、源定位诊断、JSON 报告、内置 GTFS 领域档案 | 聚焦多表关系完整性；不读 JSONL、不做 schema 推断或质量评分 |

## 核对方法

以上描述中，moon-csv-lite 与 moonverity 依据其在 Mooncakes 上的公开文档（函数签名与 README）整理，未运行其代码；wayfarer 的描述依据本仓库源码。Wayfarer 尚未发布到 Mooncakes 索引，其版本与文档以 GitHub 仓库为准。Wayfarer 不宣称生态中不存在其他 CSV 工具，仅主张上述差异化能力在核对时点未被上述相邻项目覆盖。
