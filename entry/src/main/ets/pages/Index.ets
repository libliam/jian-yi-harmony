/**
 * 简忆 · 主容器
 *
 * 五个主视图用条件渲染切换（不用 Tabs 自带 bar），底部标签栏自绘，
 * 这样才能和原型那套纸墨风格对上。所有导航状态放 AppStorage，见 common/Bus.ets。
 *
 * 注意：这里的单页 + 覆盖层是过渡实现。系统返回键由 onBackPress 逐层接管，
 * 终态应换成 Navigation / router 的真实页面栈，见 AGENTS.md 第 4 节。
 */

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { initDb } from '../db/JianYiDb';
import { seedDemoDataIfEmpty } from '../db/Seed';
import {
  ensureUiState, bumpRevision, switchTab, openSheet,
  closeSheet, closeSearch, closeSub
} from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';
import { TodayView } from '../view/TodayView';
import { QuoteView } from '../view/QuoteView';
import { TodoView } from '../view/TodoView';
import { ReaderView } from '../view/ReaderView';
import { PlanView } from '../view/PlanView';
import { SearchPanel } from '../view/SearchPanel';
import { QuickSheet } from '../view/QuickSheet';
import { SubPages } from '../view/SubPages';

interface TabItem {
  mark: string;
  label: string;
}

const TABS: TabItem[] = [
  { mark: '日', label: '今日' },
  { mark: '句', label: '语录' },
  { mark: '办', label: '待办' },
  { mark: '书', label: '阅读' },
  { mark: '划', label: '计划' }
];

@Entry
@Component
struct Index {
  @StorageLink('uiTab') currentTab: number = 0;
  @StorageLink('uiSearch') showSearch: boolean = false;
  @StorageLink('uiSheet') sheetType: string = '';
  @StorageLink('uiSub') subPage: string = '';
  @State ready: boolean = false;
  @State error: string = '';
  private lastBackAt: number = 0;

  async aboutToAppear(): Promise<void> {
    ensureUiState();
    const context: common.Context = getContext(this) as common.Context;
    try {
      await initDb(context);
      // 开发期示例数据，只在首次启动写入；失败不影响主流程
      try {
        await seedDemoDataIfEmpty(context);
      } catch (seedErr) {
        // 示例数据可有可无，不阻断应用
      }
      this.ready = true;
    } catch (err) {
      this.error = '数据库没能打开。请确认设备存储可用后重新进入。';
    }
  }

  /** 从后台 / 桌面回到前台时重拉一次数据，各视图用 @Watch('dbRevision') 刷新 */
  onPageShow(): void {
    if (this.ready) {
      bumpRevision();
    }
  }

  /**
   * 系统返回键与侧滑返回。
   * 返回 true = 自己消费掉这次返回；返回 false = 交给系统，应用退到后台。
   * 顺序按用户可见的层级从上往下：录入弹层 → 搜索 → 二级页 → 回今日 → 二次确认退出。
   */
  onBackPress(): boolean {
    if (this.sheetType.length > 0) {
      closeSheet();
      return true;
    }
    if (this.showSearch) {
      closeSearch();
      return true;
    }
    if (this.subPage.length > 0) {
      closeSub();
      return true;
    }
    if (this.currentTab !== 0) {
      switchTab(0);
      return true;
    }
    const now: number = Date.now();
    if (now - this.lastBackAt < 2000) {
      return false;
    }
    this.lastBackAt = now;
    promptAction.showToast({ message: '再按一次返回，退出简忆', duration: 2000 });
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (!this.ready) {
          Column() {
            Text(this.error.length > 0 ? this.error : '正在打开简忆…')
              .fontSize(13)
              .fontColor(C.ink3)
              .textAlign(TextAlign.Center)
              .padding(30)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.currentTab === 0) {
              TodayView()
            } else if (this.currentTab === 1) {
              QuoteView()
            } else if (this.currentTab === 2) {
              TodoView()
            } else if (this.currentTab === 3) {
              ReaderView()
            } else {
              PlanView()
            }
          }
          .width('100%')
          .layoutWeight(1)
        }

        this.tabbar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(C.paper)

      // 全局悬浮：快速记录。搜索/弹层/二级页打开时让位
      if (this.ready && !this.showSearch && this.sheetType.length === 0 && this.subPage.length === 0) {
        Button() {
          Text('＋')
            .fontSize(24)
            .fontColor(C.paper)
            .fontWeight(FontWeight.Normal)
        }
        .width(50)
        .height(50)
        .borderRadius(25)
        .backgroundColor(C.ink)
        .shadow({ radius: 24, color: '#331B1917', offsetX: 0, offsetY: 10 })
        .margin({ right: 22, bottom: S.tabbarHeight + 22 })
        .zIndex(10)
        .onClick(() => openSheet('more'))
      }

      if (this.showSearch) {
        SearchPanel()
      }
      if (this.subPage.length > 0) {
        SubPages()
      }
      if (this.sheetType.length > 0) {
        QuickSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabbar() {
    Row() {
      ForEach(TABS, (item: TabItem, index: number) => {
        Column() {
          Text(item.mark)
            .fontFamily(SERIF)
            .fontSize(17)
            .fontColor(this.currentTab === index ? C.ink : C.ink3)
          Text(item.label)
            .fontSize(9.5)
            .fontColor(this.currentTab === index ? C.ink : C.ink3)
            .margin({ top: 3 })
          Row()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(C.cinnabar)
            .margin({ top: 5 })
            .opacity(this.currentTab === index ? 1 : 0)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => switchTab(index))
      }, (item: TabItem, index: number) => `${index}-${item.label}`)
    }
    .width('100%')
    .height(S.tabbarHeight)
    .padding({ left: 12, right: 12, bottom: 8 })
    .backgroundColor(C.paper)
    .border({ width: { top: 1 }, color: C.ruleSoft })
    .zIndex(5)
  }
}
