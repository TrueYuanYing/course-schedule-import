# 实现与来源

本 SDK 为独立实现，复用本项目自编的 parser.js/provider.js 及事实入口目录。不包含 WakeUp 的品牌素材、混淆运行时代码、私有接口密钥或加密配置原文。

导入机制研究依据公开源码与用户授权下载的 WakeUp 6.5.0 APK 静态结构：

- WakeUp 官网：https://wakeup.fun/
- CourseAdapter（公开 Java 解析器，MIT）：https://github.com/NYIST-CIPS/CourseAdapter
- 早期 WakeupSchedule_BUPT（历史源码，Apache-2.0）：https://github.com/xianfei/WakeupSchedule_BUPT
- 东北大学公开格式研究：https://github.com/CreamPig233/neu_wisedu2wakeup

学校目录来自 APK 的名称/公开网址字段及本次官网入口核查，包含历史、备用、研究生和待适配记录。来源描述与待验收标记保留在目录中；这不是对 WakeUp 当前适配服务的实时镜像。

测试开发依赖 jsdom 的授权由 npm 依赖包携带；不会打包进 Android AAR/APK。

## IKO 学校校徽

IKO 增加的校徽来自软科公开 2026 排名页面的校名/校徽配对数据：
https://www.shanghairanking.cn/rankings/bcur/2026 。例如武汉大学页面：
https://www.shanghairanking.cn/institution/wuhan-university 。
这些标识用于识别对应学校，不表示学校或软科对 IKO 的认可，也不属于 IKO 自创素材。
来源 URL、原图与打包资源 SHA-256 保存在主项目的
`verification/course-import-20261007/school-badge-sources.json`。
