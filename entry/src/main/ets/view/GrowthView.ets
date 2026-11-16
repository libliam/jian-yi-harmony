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
import { C, S, SERIF } from '../common/Theme';
import { today, lastNDays, formatTime } from '../common/DateUtil';

interface GrowthDayGroup {
  date: string;
  items: GrowthRow[];
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
  /**
   * 列表刷新版本号。ForEach 只按 key 判断能否复用组件：key 不变就复用旧组件、
   * 不重跑 itemBuilder。因此「改了维度」和「展开补标面板」都必须让 key 跟着变，
   * 否则数据写进库了、屏幕还是旧值。见 AGENTS.md 3.7。
   */
  @State listVersion: number = 0;
  @State hasThen: boolean = false;
  @State thenContent: string = '';
  @State thenDate: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const all: GrowthRow[] = await listAllGrowth();
    const dates: string[] = lastNDays(28);
    const thenDate: string = lastNDays(31)[0];
    const sum: GrowthSummary = summarize(
      all, dates, monthPrefix(today()), prevMonthPrefix(), thenDate
    );

    // 时间线按日分组，从新到旧，最多保留 20 天
    const groups: GrowthDayGroup[] = [];
    for (let i: number = all.length - 1; i >= 0; i--) {
      const row: GrowthRow = all[i];
      const last: GrowthDayGroup | null = groups.length > 0 ? groups[groups.length - 1] : null;
      if (last === null || last.date !== row.date) {
        if (groups.length >= 20) {
          break;
        }
        const group: GrowthDayGroup = { date: row.date, items: [] };
        groups.push(group);
      }
      groups[groups.length - 1].items.push(row);
    }

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
    this.groups = groups;
    this.heatRows = heat;
    // 数据换了一批，让下面所有 ForEach 的 key 一起失效，强制按新数据重建行
    this.listVersion = this.listVersion + 1;
  }

  private async retag(id: string, name: string): Promise<void> {
    await updateGrowthCategory(id, categoryForDb(name));
    this.editingId = '';
    bumpRevision();
    await this.load();
  }

  private async remove(id: string): Promise<void> {
    await removeGrowth(id);
    this.editingId = '';
    bumpRevision();
    await this.load();
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
    Scroll() {
      Column() {
        Row() {
          Text('‹ 返回')
            .fontSize(12.5)
            .fontColor(C.ink2)
            .onClick(() => closeGrowth())
          Blank()
          Text('＋ 记一点')
            .fontSize(12)
            .fontColor(C.cinnabar)
            .onClick(() => openSheet('growth'))
        }
        .width('100%')
        .padding({ top: 14, bottom: 18 })

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
          }, (item: CategoryCount) => `${item.name}|${item.count}|${this.listVersion}`)
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
              }, (count: number, colIndex: number) =>
                `${rowIndex}-${colIndex}|${count}|${this.listVersion}`)
            }
            .width('100%')
            .margin({ bottom: 6 })
          }, (line: number[], rowIndex: number) => `${rowIndex}|${this.listVersion}`)
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
        Text('点一下右边的维度可以补标或改掉')
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
              ForEach(group.items, (row: GrowthRow) => {
                Column() {
                  Row() {
                    Text(formatTime(row.createdAt))
                      .fontSize(10)
                      .fontColor(C.ink3)
                      .width(42)
                    Column() {
                      Text(row.content)
                        .fontSize(12.5)
                        .lineHeight(22)
                        .fontColor(C.ink)
                        .alignSelf(ItemAlign.Start)
                      if (amountLabel(row).length > 0) {
                        Text(amountLabel(row))
                          .fontSize(10)
                          .fontColor(C.ink3)
                          .margin({ top: 3 })
                          .alignSelf(ItemAlign.Start)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text(categoryLabel(row.category))
                      .fontSize(10)
                      .fontColor(categoryLabel(row.category) === '未分类' ? C.ink3 : C.cinnabar)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .borderRadius(S.pill)
                      .border({ width: 1, color: C.rule })
                      .onClick(() => {
                        this.editingId = this.editingId === row.id ? '' : row.id;
                        // 展开/收起也要重建行，否则 itemBuilder 里的 if 不会重新求值
                        this.listVersion = this.listVersion + 1;
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)

                  if (this.editingId === row.id) {
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(GROWTH_CATEGORIES, (name: string) => {
                        Text(name)
                          .fontSize(10.5)
                          .fontColor(categoryLabel(row.category) === name ? C.paper : C.ink2)
                          .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                          .borderRadius(S.pill)
                          .border({
                            width: 1,
                            color: categoryLabel(row.category) === name ? C.ink : C.rule
                          })
                          .backgroundColor(categoryLabel(row.category) === name ? C.ink : C.paper)
                          .margin({ right: 7, top: 8 })
                          .onClick(() => this.retag(row.id, name))
                      }, (name: string) => `${name}|${this.listVersion}`)
                      Text('删掉这条')
                        .fontSize(10.5)
                        .fontColor(C.cinnabar)
                        .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                        .borderRadius(S.pill)
                        .border({ width: 1, color: C.rule })
                        .margin({ top: 8 })
                        .onClick(() => this.remove(row.id))
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding({ top: 11, bottom: 11 })
                .border({ width: { bottom: 1 }, color: C.ruleSoft })
              }, (row: GrowthRow) => `${row.id}|${categoryLabel(row.category)}|${this.listVersion}`)
            }
            .width('100%')
          }, (group: GrowthDayGroup) => `${group.date}|${this.listVersion}`)
        }

        if (this.summary.earliest !== null) {
          Text('只把证据摆整齐，其余的留给你自己看。')
            .fontSize(10.5)
            .fontColor(C.ink3)
            .margin({ top: 24 })
            .alignSelf(ItemAlign.Start)
        }
      }
      .width('100%')
      .padding({ left: S.pad, right: S.pad, bottom: S.contentBottom })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
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
