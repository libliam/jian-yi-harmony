/**
 * 微光 · 回顾页内容
 *
 * 三层只摆证据：密度（条数 / 连续 / 热力）、结构（维度分布与上月对比）、
 * 原文（时间线 / 那时的我 / 常提到的词）。没有评分、没有目标、没有断签提醒。
 * 统计全部由 common/GrowthAnalysis.ets 现算，页面里不出现 SQL。
 */

import { GrowthRow } from '../db/Models';
import { listAllGrowth, updateGrowthCategory, removeGrowth } from '../db/GrowthRepo';
import {
  GrowthSummary, CategoryCount, summarize, monthPrefix, prevMonthPrefix,
  compareText, newCategoryText
} from '../common/GrowthAnalysis';
import {
  GROWTH_CATEGORIES, categoryForDb, categoryLabel, amountLabel
} from '../common/GrowthTag';
import { bumpRevision, closeGrowth, openSheet } from '../common/Bus';
import { exportMonthlySummary, exportAllData, ExportResult } from '../common/DataExport';
import { isLockEnabled, setLockEnabled, hasBiometric } from '../common/AppLock';
import { common } from '@kit.AbilityKit';
import { C, S, SERIF } from '../common/Theme';
import { today, lastNDays, formatTime } from '../common/DateUtil';

/**
 * 渲染用包装：把「会变的展示字段与展开状态」算进 viewKey。
 * ForEach 的 keyGenerator 必须是纯函数、只读 item 自身字段；一旦在里面读组件状态变量
 * （例如上版的 listVersion），框架未必重算 key，数据更新了界面却不动。见 AGENTS.md 3.7。
 */
interface GrowthItem {
  row: GrowthRow;
  viewKey: string;
}

interface GrowthDayGroup {
  date: string;
  items: GrowthItem[];
  /** 汇总组内所有行的 viewKey：任一行变化，整组都要换 key 才能重建内层列表 */
  viewKey: string;
}

function emptySummary(): GrowthSummary {
  return {
    total: 0, monthCount: 0, prevMonthCount: 0, streak: 0,
    days: [], categories: [], prevCounts: [], topWords: [],
    totalMinutes: 0, thenRow: null, earliest: null
  };
}

@Component
export struct GrowthView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State summary: GrowthSummary = emptySummary();
  @State groups: GrowthDayGroup[] = [];
  @State heatRows: number[][] = [];
  @State editingId: string = '';
  /** 最近一次读到的全量数据：点标签展开时用它同步重算 viewKey，不必再读库 */
  @State allRows: GrowthRow[] = [];
  /** 原生下拉刷新组件的双向绑定状态 */
  @State refreshing: boolean = false;
  @State hasThen: boolean = false;
  @State thenContent: string = '';
  @State thenDate: string = '';
  @State exportHint: string = '';
  @State lockOn: boolean = false;
  @State biometricReady: boolean = false;

  /** 应用锁开关：开启前先确认设备录入了人脸 / 指纹，避免开了却解不开 */
  private async toggleLock(on: boolean): Promise<void> {
    if (on && !this.biometricReady) {
      this.exportHint = '请先在系统设置里录入指纹或面容，再开启应用锁。';
      return;
    }
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      await setLockEnabled(ctx, on);
      this.lockOn = on;
      this.exportHint = on ? '应用锁已开启，每次回到简忆都要验证。' : '应用锁已关闭。';
    } catch (err) {
      this.exportHint = '设置失败，请重试。';
    }
  }

  /** 导出本月小结到用户选的位置 */
  private async exportMonth(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const month: string = monthPrefix(today());
      const result: ExportResult = await exportMonthlySummary(ctx, this.summary, month, this.allRows);
      this.exportHint = result.message;
    } catch (err) {
      this.exportHint = '导出失败，请重试。';
    }
  }

  /** 导出全部数据备份（JSON） */
  private async exportBackup(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result: ExportResult = await exportAllData(ctx);
      this.exportHint = result.message;
    } catch (err) {
      this.exportHint = '导出失败，请重试。';
    }
  }

  async aboutToAppear(): Promise<void> {
    this.biometricReady = hasBiometric();
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      this.lockOn = await isLockEnabled(ctx);
    } catch (err) {
      this.lockOn = false;
    }
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const all: GrowthRow[] = await listAllGrowth();
    this.allRows = all;
    const dates: string[] = lastNDays(28);
    const thenDate: string = lastNDays(31)[0];
    const sum: GrowthSummary = summarize(
      all, dates, monthPrefix(today()), prevMonthPrefix(), thenDate
    );

    const heat: number[][] = [];
    for (let r: number = 0; r < 4; r++) {
      const line: number[] = [];
      for (let c: number = 0; c < 7; c++) {
        const index: number = r * 7 + c;
        let value: number = 0;
        if (index < sum.days.length) {
          value = sum.days[index];
        }
        line.push(value);
      }
      heat.push(line);
    }

    const thenRow: GrowthRow | null = sum.thenRow;
    if (thenRow !== null) {
      this.hasThen = true;
      this.thenContent = thenRow.content;
      this.thenDate = thenRow.date;
    } else {
      this.hasThen = false;
      this.thenContent = '';
      this.thenDate = '';
    }

    this.summary = sum;
    this.groups = this.makeGroups(all);
    this.heatRows = heat;
  }

  /**
   * 时间线按日分组，从新到旧，最多 20 天。
   * 行的 viewKey 带上维度、updatedAt 与展开状态；组的 viewKey 再汇总组内所有行，
   * 任一行变化都会让整组换 key → 外层重建 → 内层 ForEach 拿到的是新数据。
   */
  private makeGroups(all: GrowthRow[]): GrowthDayGroup[] {
    const groups: GrowthDayGroup[] = [];
    for (let i: number = all.length - 1; i >= 0; i--) {
      const row: GrowthRow = all[i];
      const last: GrowthDayGroup | null = groups.length > 0 ? groups[groups.length - 1] : null;
      if (last === null || last.date !== row.date) {
        if (groups.length >= 20) {
          break;
        }
        const group: GrowthDayGroup = { date: row.date, items: [], viewKey: '' };
        groups.push(group);
      }
      const item: GrowthItem = { row: row, viewKey: this.itemKey(row) };
      groups[groups.length - 1].items.push(item);
    }
    for (const group of groups) {
      let joined: string = '';
      for (const item of group.items) {
        joined = joined + item.viewKey + '~';
      }
      group.viewKey = `${group.date}|${joined}`;
    }
    return groups;
  }

  /** 补标会同时更新 updated_at，所以维度一改，这个 key 必定变化 */
  private itemKey(row: GrowthRow): string {
    const editing: string = this.editingId === row.id ? 'open' : 'closed';
    return `${row.id}|${categoryLabel(row.category)}|${row.updatedAt}|${editing}`;
  }

  private async retag(id: string, name: string): Promise<void> {
    await updateGrowthCategory(id, categoryForDb(name));
    this.editingId = '';
    await this.load();
    bumpRevision();
  }

  private async remove(id: string): Promise<void> {
    await removeGrowth(id);
    this.editingId = '';
    await this.load();
    bumpRevision();
  }

  private maxCategory(): number {
    let max: number = 0;
    for (const item of this.summary.categories) {
      if (item.count > max) {
        max = item.count;
      }
    }
    return max;
  }

  private barPercent(count: number): string {
    const max: number = this.maxCategory();
    if (max === 0 || count === 0) {
      return '0%';
    }
    return `${Math.round(count * 100 / max)}%`;
  }

  private dayLabel(date: string): string {
    const parts: string[] = date.split('-');
    return `${Number(parts[1])} 月 ${Number(parts[2])} 日`;
  }

  build() {
    // 原生下拉刷新：写入后总线会自动刷新，这里再给一个用户可主动触发的系统手势
    Refresh({ refreshing: $$this.refreshing }) {
    Scroll() {
      Column() {
        Row() {
          Text('‹ 返回')
            .fontSize(12.5)
            .fontColor(C.ink2)
            .onClick(() => closeGrowth())
          Blank()
          Text('导出小结')
            .fontSize(11.5)
            .fontColor(C.ink3)
            .margin({ right: 16 })
            .onClick(() => this.exportMonth())
          Text('＋ 记一点')
            .fontSize(12)
            .fontColor(C.cinnabar)
            .onClick(() => openSheet('growth'))
        }
        .width('100%')
        .padding({ top: 14, bottom: 18 })

        if (this.exportHint.length > 0) {
          Text(this.exportHint)
            .fontSize(10.5)
            .fontColor(C.sage)
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 8 })
        }

        Text('微光 · 回顾')
          .fontFamily(SERIF)
          .fontSize(24)
          .fontColor(C.ink)
          .alignSelf(ItemAlign.Start)
        Text('一点一点，攒起来才看得见。')
          .fontSize(11.5)
          .fontColor(C.ink3)
          .margin({ top: 6, bottom: 18 })
          .alignSelf(ItemAlign.Start)

        Row() {
          this.metric('本月', `${this.summary.monthCount}`)
          this.metric('连续', `${this.summary.streak}`)
          this.metric('累计', `${this.summary.total}`)
        }
        .width('100%')

        Text(compareText(this.summary))
          .fontSize(11)
          .fontColor(C.ink2)
          .margin({ top: 12 })
          .alignSelf(ItemAlign.Start)
        if (this.summary.totalMinutes > 0) {
          Text(`这个月记下的时长，合起来约 ${this.summary.totalMinutes} 分钟`)
            .fontSize(11)
            .fontColor(C.ink3)
            .margin({ top: 5 })
            .alignSelf(ItemAlign.Start)
        }

        // —— 结构：维度分布与上月对比
        Text('这段日子，长在哪儿')
          .fontFamily(SERIF)
          .fontSize(15)
          .fontColor(C.ink)
          .margin({ top: 26, bottom: 12 })
          .alignSelf(ItemAlign.Start)

        Column() {
          ForEach(this.summary.categories, (item: CategoryCount) => {
            Row() {
              Text(item.name)
                .fontSize(10.5)
                .fontColor(C.ink2)
                .width(38)
              Row() {
                Row()
                  .width(this.barPercent(item.count))
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor(item.name === '未分类' ? C.ink3 : C.cinnabar)
              }
              .layoutWeight(1)
              .height(6)
              .borderRadius(3)
              .backgroundColor(C.ruleSoft)
              Text(`${item.count}`)
                .fontSize(10.5)
                .fontColor(C.ink3)
                .width(24)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .margin({ bottom: 9 })
          }, (item: CategoryCount) => `${item.name}|${item.count}`)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .border({ width: 1, color: C.rule })
        .backgroundColor(C.paper2)

        if (newCategoryText(this.summary).length > 0) {
          Text(newCategoryText(this.summary))
            .fontSize(11)
            .fontColor(C.cinnabar)
            .margin({ top: 10 })
            .alignSelf(ItemAlign.Start)
        }
        if (this.summary.topWords.length > 0) {
          Text(`常提到：${this.summary.topWords.join('　')}`)
            .fontSize(11)
            .fontColor(C.ink3)
            .margin({ top: 10 })
            .alignSelf(ItemAlign.Start)
        }

        // —— 密度：近四周热力
        Text('近四周')
          .fontFamily(SERIF)
          .fontSize(15)
          .fontColor(C.ink)
          .margin({ top: 26, bottom: 12 })
          .alignSelf(ItemAlign.Start)

        Column() {
          ForEach(this.heatRows, (line: number[], rowIndex: number) => {
            Row() {
              ForEach(line, (count: number, colIndex: number) => {
                Row()
                  .width(26)
                  .height(26)
                  .borderRadius(5)
                  .backgroundColor(count > 0 ? C.cinnabar : C.ruleSoft)
                  .opacity(count > 2 ? 1 : count > 0 ? 0.55 : 1)
                  .margin({ right: 6 })
              }, (count: number, colIndex: number) => `${rowIndex}-${colIndex}|${count}`)
            }
            .width('100%')
            .margin({ bottom: 6 })
          }, (line: number[], rowIndex: number) => `${rowIndex}|${line.join(',')}`)
          Text('有记录的日子会亮一点；空着也没关系。')
            .fontSize(10.5)
            .fontColor(C.ink3)
            .margin({ top: 6 })
            .alignSelf(ItemAlign.Start)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .border({ width: 1, color: C.rule })
        .backgroundColor(C.paper2)

        // —— 原文：那时的我
        if (this.hasThen) {
          Text('那时的我')
            .fontFamily(SERIF)
            .fontSize(15)
            .fontColor(C.ink)
            .margin({ top: 26, bottom: 12 })
            .alignSelf(ItemAlign.Start)
          Column() {
            Text('一个月前')
              .fontSize(10)
              .fontColor(C.ink3)
              .alignSelf(ItemAlign.Start)
            Text(this.thenContent)
              .fontFamily(SERIF)
              .fontSize(14)
              .lineHeight(26)
              .fontColor(C.ink)
              .margin({ top: 10 })
              .alignSelf(ItemAlign.Start)
            Text(this.thenDate)
              .fontSize(10)
              .fontColor(C.ink3)
              .margin({ top: 10 })
              .alignSelf(ItemAlign.Start)
          }
          .width('100%')
          .padding(18)
          .borderRadius(16)
          .border({ width: 1, color: C.rule })
          .backgroundColor(C.paper2)
        }

        // —— 原文：按日时间线
        Text('一点一点')
          .fontFamily(SERIF)
          .fontSize(15)
          .fontColor(C.ink)
          .margin({ top: 26, bottom: 6 })
          .alignSelf(ItemAlign.Start)
        Text('点维度可补标或改掉 · 下拉可以刷新')
          .fontSize(10.5)
          .fontColor(C.ink3)
          .margin({ bottom: 10 })
          .alignSelf(ItemAlign.Start)

        if (this.groups.length === 0) {
          Text('还没有记录。回今日页写第一点就好。')
            .fontSize(11.5)
            .fontColor(C.ink3)
            .margin({ top: 20 })
            .alignSelf(ItemAlign.Start)
        } else {
          ForEach(this.groups, (group: GrowthDayGroup) => {
            Column() {
              Text(this.dayLabel(group.date))
                .fontSize(10)
                .fontColor(C.ink3)
                .letterSpacing(2)
                .margin({ top: 16, bottom: 6 })
                .alignSelf(ItemAlign.Start)
              ForEach(group.items, (item: GrowthItem) => {
                Column() {
                  Row() {
                    Text(formatTime(item.row.createdAt))
                      .fontSize(10)
                      .fontColor(C.ink3)
                      .width(42)
                    Column() {
                      Text(item.row.content)
                        .fontSize(12.5)
                        .lineHeight(22)
                        .fontColor(C.ink)
                        .alignSelf(ItemAlign.Start)
                      if (amountLabel(item.row).length > 0) {
                        Text(amountLabel(item.row))
                          .fontSize(10)
                          .fontColor(C.ink3)
                          .margin({ top: 3 })
                          .alignSelf(ItemAlign.Start)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text(categoryLabel(item.row.category))
                      .fontSize(10)
                      .fontColor(categoryLabel(item.row.category) === '未分类' ? C.ink3 : C.cinnabar)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .borderRadius(S.pill)
                      .border({ width: 1, color: C.rule })
                      .onClick(() => {
                        this.editingId = this.editingId === item.row.id ? '' : item.row.id;
                        // 用缓存数据同步重算 viewKey：不读库，展开/收起立即生效
                        this.groups = this.makeGroups(this.allRows);
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)

                  if (this.editingId === item.row.id) {
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(GROWTH_CATEGORIES, (name: string) => {
                        Text(name)
                          .fontSize(10.5)
                          .fontColor(categoryLabel(item.row.category) === name ? C.paper : C.ink2)
                          .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                          .borderRadius(S.pill)
                          .border({
                            width: 1,
                            color: categoryLabel(item.row.category) === name ? C.ink : C.rule
                          })
                          .backgroundColor(categoryLabel(item.row.category) === name ? C.ink : C.paper)
                          .margin({ right: 7, top: 8 })
                          .onClick(() => this.retag(item.row.id, name))
                      }, (name: string) => name)
                      Text('删掉这条')
                        .fontSize(10.5)
                        .fontColor(C.cinnabar)
                        .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                        .borderRadius(S.pill)
                        .border({ width: 1, color: C.rule })
                        .margin({ top: 8 })
                        .onClick(() => this.remove(item.row.id))
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding({ top: 11, bottom: 11 })
                .border({ width: { bottom: 1 }, color: C.ruleSoft })
              }, (item: GrowthItem) => item.viewKey)
            }
            .width('100%')
          }, (group: GrowthDayGroup) => group.viewKey)
        }

        if (this.summary.earliest !== null) {
          Text('只把证据摆整齐，其余的留给你自己看。')
            .fontSize(10.5)
            .fontColor(C.ink3)
            .margin({ top: 24 })
            .alignSelf(ItemAlign.Start)
        }

        Text('导出全部数据备份')
          .fontSize(10.5)
          .fontColor(C.ink3)
          .decoration({ type: TextDecorationType.Underline, color: C.rule })
          .margin({ top: 20 })
          .alignSelf(ItemAlign.Start)
          .onClick(() => this.exportBackup())

        Row() {
          Text('应用锁（指纹 / 面容）')
            .fontSize(12)
            .fontColor(C.ink2)
          Toggle({ type: ToggleType.Switch, isOn: this.lockOn })
            .selectedColor(C.cinnabar)
            .width(40)
            .height(22)
            .onChange((on: boolean) => this.toggleLock(on))
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 24 })

        Text(this.exportHint)
          .fontSize(10.5)
          .fontColor(C.ink3)
          .margin({ top: 8 })
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .padding({ left: S.pad, right: S.pad, bottom: S.contentBottom })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    }
    .onRefreshing(() => {
      this.load().then(() => {
        this.refreshing = false;
      }).catch(() => {
        // 读库失败也要收起刷新头，不能把用户卡在「正在刷新」
        this.refreshing = false;
      });
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  metric(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(10.5)
        .fontColor(C.ink3)
      Text(value)
        .fontFamily(SERIF)
        .fontSize(24)
        .fontColor(C.ink)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .borderRadius(S.smallRadius)
    .backgroundColor(C.paper2)
  }
}
