# Wayfarer 使用场景

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/) 后，在仓库根目录运行 `moon update`。以下输入均为仓库内的合成样例。

## 课程目录交接

课程与场次由同一批任务分别导出。接入方在导入前运行目录检查，凭文件名和行列定位导出错误。用同一份契约对比损坏与正常的导出结果。

```text
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog-malformed --json
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog --json
```

损坏目录返回 `2`，一次报告 `courses.csv:2` 的列数不符和 `sessions.csv:2:7` 的引号未闭合。正常目录返回 `0`，报告中的 `passed` 为 `true`。这组用例复现[十一月新增的输入诊断](csv-input-diagnostics.md)。

## 选课数据导入门禁

导入任务读取班级、学员、选课三张表。先按契约校验班级引用和「学员＋班级」组合唯一键。在 CI 中以退出码决定是否继续导入，并保存 JSON 供维护者定位。

```text
moon run cmd/csv-check examples/enrollment-profile.json examples/enrollment-profile-invalid --json
moon run cmd/csv-check examples/enrollment-profile.json examples/enrollment-profile --json
```

错误目录返回 `1`。`enrollments.csv:2` 引用了未知班级，`enrollments.csv:4` 重复登记同一学员和班级。正常目录返回 `0`。

## 固定站点 GTFS 发布前预检

数据维护者在发布前对解压目录运行内置档案，检查行程与服务日历、站点等关系。

```text
moon run cmd/main examples/no-service-calendar
moon run cmd/main examples/valid
```

缺失服务日历的样例返回 `1`。正常样例处理 7 个文件、9 条记录，返回 `0`。支持范围见 [GTFS 档案说明](../README.md#built-in-gtfs-schedule-profile)。
