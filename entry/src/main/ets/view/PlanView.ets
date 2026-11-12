/**
 * 计划页
 *
 * 周条 + 时间块，数据来自 event 表。选中的日期通过 Bus 传给录入弹层，
 * 保证「在周三加一段安排」不会落到今天去。
 */

import { EventRow } from '../db/Models';
import { listEventsByDate, listEventsInRange } from '../db/EventRepo';
import { setPlanDate, openSheet } from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';
import { DayCell, currentWeek, today, formatTime } from '../common/DateUtil';
import { PageHead } from './Parts';

@Component
export struct PlanView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State week: DayCell[] = [];
  @State selected: string = '';
  @State events: EventRow[] = [];
  @State rangeEvents: EventRow[] = [];

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.week = currentWeek();
    if (this.selected.length === 0) {
      this.selected = today();
    }
    setPlanDate(this.selected);
    this.events = await listEventsByDate(this.selected);
    this.rangeEvents = await listEventsInRange(this.week[0].date, this.week[6].date);
  }

  private async pickDay(date: string): Promise<void> {
    this.selected = date;
    setPlanDate(date);
    this.events = await listEventsByDate(date);
  }

  private hasEvent(date: string): boolean {
    for (const e of this.rangeEvents) {
      if (e.date === date) {
        return true;
      }
    }
    return false;
  }

  private monthText(): string {
    const parts: string[] = this.selected.split('-');
    return parts.length === 3 ? `${Number(parts[1])} 月` : '本月';
  }

  private advice(): string {
    if (this.events.length === 0) {
      return '这一天还空着。挑一件最想专心做的事，给它留一段时间。';
    }
    return `${this.events.length} 段安排已经排开。相邻两段之间记得留出空档，赶场最容易把一天耗掉。`;
  }

  build() {
    Column() {
      PageHead({ eyebrow: 'Plan', title: '计划', meta: this.monthText() })

      // 周条
      Row() {
        ForEach(this.week, (cell: DayCell) => {
          Column() {
            Text(cell.dow)
              .fontSize(9.5)
              .fontColor(this.selected === cell.date ? C.paper2 : C.ink3)
            Text(cell.num)
              .fontFamily(SERIF)
              .fontSize(16)
              .fontColor(this.selected === cell.date ? C.paper : C.ink)
              .margin({ top: 6 })
            Row()
              .width(3)
              .height(3)
              .borderRadius(2)
              .backgroundColor(this.hasEvent(cell.date) ? C.cinnabar : C.paper2)
              .margin({ top: 5 })
          }
          .layoutWeight(1)
          .padding({ top: 8, bottom: 8 })
          .borderRadius(S.smallRadius)
          .backgroundColor(this.selected === cell.date ? C.ink : C.paper)
          .onClick(() => this.pickDay(cell.date))
        }, (cell: DayCell) => cell.date)
      }
      .width('100%')
      .padding({ top: 6, bottom: 22 })

      Scroll() {
        Column() {
          if (this.events.length === 0) {
            Column() {
              Text('这一天还没有排下时间段。\n把最想专心做的那件事放进来吧。')
                .fontSize(11.5)
                .lineHeight(22)
                .fontColor(C.ink3)
                .textAlign(TextAlign.Center)
              Button('加一段安排')
                .fontSize(11)
                .fontColor(C.ink2)
                .backgroundColor(C.paper)
                .border({ width: 1, color: C.rule })
                .borderRadius(S.pill)
                .padding({ left: 18, right: 18, top: 9, bottom: 9 })
                .margin({ top: 18 })
                .onClick(() => openSheet('event'))
            }
            .width('100%')
            .padding({ top: 36, bottom: 30 })
          } else {
            ForEach(this.events, (e: EventRow, index: number) => {
              this.slot(e, index === 0 && this.selected === today())
            }, (e: EventRow) => e.id)
          }

          // 一点建议：本地规则生成，不联网、不上传
          Row() {
            Text('✦')
              .fontSize(11)
              .fontColor(C.cinnabar)
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor(C.cinnabarSoft)
              .textAlign(TextAlign.Center)
              .margin({ right: 12 })
            Text() {
              Span('一点建议　').fontWeight(FontWeight.Bold).fontColor(C.ink)
              Span(this.advice()).fontColor(C.ink2)
            }
            .fontSize(11.5)
            .lineHeight(21)
            .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 8 })
          .padding(15)
          .borderRadius(14)
          .border({ width: 1, color: C.rule })
          .alignItems(VerticalAlign.Top)

          Button('＋　加一段安排')
            .fontSize(12)
            .fontColor(C.ink3)
            .backgroundColor(C.paper)
            .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
            .borderRadius(14)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .margin({ top: 22 })
            .onClick(() => openSheet('event'))
        }
        .width('100%')
        .padding({ bottom: S.contentBottom })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: S.pad, right: S.pad })
  }

  private slotTimeText(e: EventRow): string {
    const end: string = e.endAt === null ? '' : formatTime(e.endAt);
    return end.length > 0 ? `${formatTime(e.startAt)} – ${end}` : '时间待定';
  }

  @Builder
  slot(e: EventRow, focus: boolean) {
    Row() {
      Text(formatTime(e.startAt))
        .fontSize(11)
        .fontColor(C.ink3)
        .width(46)
        .margin({ top: 14 })

      Column() {
        Row()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(focus ? C.cinnabar : C.paper)
          .border({ width: 1, color: focus ? C.cinnabar : C.ink3 })
          .margin({ top: 18 })
        Row()
          .width(1)
          .height(56)
          .backgroundColor(C.rule)
      }
      .width(7)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text(e.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(focus ? C.darkText : C.ink)
        Text(this.slotTimeText(e))
          .fontSize(10.5)
          .fontColor(focus ? C.darkSub : C.ink3)
          .margin({ top: 5 })
        if (focus) {
          Text('进行中')
            .fontSize(9.5)
            .fontColor('#D9B9A6')
            .margin({ top: 9 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 15, right: 15, top: 13, bottom: 13 })
      .borderRadius(S.smallRadius)
      .backgroundColor(focus ? C.dark : C.paper2)
      .margin({ left: 14, bottom: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
