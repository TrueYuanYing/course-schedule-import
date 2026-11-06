# 课表管理与教务导入

抽取实际 APK 使用的 `provider.js`、`parser.js`、`watch.js`，保留 DOM/已加载 JSON/通用格式解析及作息提取。Node 示例使用合成页面，不要求学校账号。Flutter 周表、列表、日历与 Android WebView 接入代码放在 reference。

```sh
# Node >=22.12，验证环境 Node 24.18.0
npm ci
node example/parse.cjs
npm test
```

示例输出“合成数学”、星期2、1–2节、1–16周与明确的08:00–08:45作息。`parseImport(html,{DOMParser})` 与 `parseCapture(capture,{DOMParser})` 是主要入口；`JSDOM` 只用于 Node 测试，不进入 Android 运行时。

[接入与新增学校适配](docs/ARCHITECTURE.md) · [测试结果](VALIDATION.md) · [来源说明](NOTICE.md) · [第三方边界](THIRD-PARTY.md)

本仓库不包含校徽、原学校数据库、真实登录页快照或用户课表。全国逐校、所有机型与整学期作息没有全部验收。截图 OCR 在原产品中使用本机 ML Kit Chinese，不上传、不耗模型 API；艺术字课程名仍需人工核对，未训练新 OCR 模型。
