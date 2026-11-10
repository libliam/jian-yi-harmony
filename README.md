# 简忆 · jian-yi-harmony

一款鸿蒙原生的个人心智工具：记下值得记住的句子，安排今天要做的事，读完手里的书。

## 当前进度

| 模块 | 状态 | 说明 |
|---|---|---|
| 交互原型 | ✅ 完成 | 单文件 HTML，浏览器直接打开 |
| 数据层 | ✅ 完成 | 7 张表 + 5 个仓库，ArkTS 参考实现 |
| ArkUI 页面 | ⬜ 未开始 | 需要 DevEco Studio |
| 通知提醒 | ⬜ 未开始 | 需要真机或模拟器 |
| 电子书阅读 | ⬜ 未开始 | 基于 Reader Kit |
| 云备份 | ⬜ 未开始 | BackupExtensionAbility |

## 快速预览

直接用浏览器打开 [`jianyi-prototype.html`](./jianyi-prototype.html)，无需安装任何环境。

五个主页面（今日 / 待办 / 语录 / 阅读 / 计划）、全局搜索、四宫格快速记录都可以真实点击。

## 目录结构

```
jianyi-prototype.html     可交互原型（唯一的产品事实来源）
harmony-data/
  Models.ets              7 张表的类型定义
  JianYiDb.ets            建表、版本迁移、记忆条目与待办读写
  RowUtil.ets             ResultSet 取值助手
  ThoughtRepo.ets         待思
  HabitRepo.ets           习惯与打卡
  MoodRepo.ets            心情
  BookRepo.ets            书籍与阅读进度
  EventRepo.ets           日程时间块
```

## 数据层

数据库为本地 RelationalStore（SQLite），文件 `databases/jianyi.db`。

三条贯穿全局的规则：

1. **主键用 UUID**，不用自增，为跨端同步留路
2. **软删除**，`deleted_at` 置时间戳，物理删除会让同步时记录复活
3. **派生数据不落库**，例如习惯连续天数，查询时现算

接入方式：

```typescript
// EntryAbility.ets
import { initDb } from '../db/JianYiDb';

onCreate(want, launchParam): void {
  initDb(this.context);
}
```

> 这份代码是参考实现，接口名请以你所用 SDK 版本的 `.d.ts` 为准。

## 开发环境

**本地（推荐）**：DevEco Studio 5.0+，Windows 10/11 或 macOS 12.5+，内存 16GB 起。
仅开发和预览可不开模拟器，写完代码用云调试跑真机，能省下一大半内存。

**云端（试用）**：[鸿蒙开发实践中心](https://harmonybp.developer.huaweicloud.com/)
浏览器内编码、打包、调试，无需安装。但它是**案例制**——选择一个案例后自动加载该案例工程，
适合学习与验证流程，不保证能直接托管本仓库。

**云端（付费）**：华为云 Windows ECS + 远程桌面，在云主机里装 DevEco Studio。
DevEco Studio 不支持 Linux，纯 Linux 云主机走不通。

## 路线图

1. 环境就绪，跑通 Hello World
2. 待办页：列表 + 新增 + 勾选（验证数据层）
3. 语录页 + 全局搜索
4. 习惯、心情、待思
5. 通知提醒
6. 电子书阅读
7. 云备份与手动导出

## 约定

编码规范、命名规则与协作约定见 [.trae/rules/project_rules.md](./.trae/rules/project_rules.md)。
