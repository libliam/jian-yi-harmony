/**
 * 今日页 · 路线图第 4 步
 *
 * 首页所有数字都是现算的派生数据：待办进度、习惯连续天数、
 * 今日心情、周心情柱、今日安排，全部来自各个仓库，没有一份硬编码。
 */

import { common } from '@kit.AbilityKit';
import { TodoRow, HabitRow, MoodRow, EventRow, TodoBucket } from '../db/Models';
import { todayBrief, countTodos, TodoStat } from '../db/TodoRepo';
import { listHabits, listDoneDates, habitStreak } from '../db/HabitRepo';
import { latestMood, listMoods, addMood } from '../db/MoodRepo';
import { listEventsByDate } from '../db/EventRepo';
import { bumpRevision, switchTab, openSub, openSheet } from '../common/Bus';
import {
  isReviewEnabled, enableReview, disableReview, REVIEW_HOUR, REVIEW_MINUTE
} from '../common/Reminder';
import { C, S, SERIF, MOOD_LABELS, priorityColor } from '../common/Theme';
import {
  DayCell, today, todayBig, monthLabel, weekdayLabel, yearLabel,
  lastSevenDays, formatTime, dueLabel, isOverdue
} from '../common/DateUtil';
import { SearchButton } from './Parts';

interface HabitBrief {
  id: string;
  name: string;
  done: boolean;
  streak: number;
  dots: boolean[];
}

@Component
export struct TodayView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State brief: TodoRow[] = [];
  @State stat: TodoStat = { total: 0, done: 0, overdue: 0 };
  @State habits: HabitBrief[] = [];
  @State moodLevel: number = 0;
  @State weekMoods: number[] = [0, 0, 0, 0, 0, 0, 0];
  @State events: EventRow[] = [];
  @State reviewOn: boolean = false;
  @State reviewHint: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
    try {
      this.reviewOn = await isReviewEnabled(getContext(this) as common.Context);
    } catch (err) {
      this.reviewOn = false;
    }
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const day: string = today();
    const week: DayCell[] = lastSevenDays();
    const from: string = week[0].date;
    const to: string = week[6].date;

    this.brief = await todayBrief(3);
    this.stat = await countTodos(TodoBucket.Today);

    const rows: HabitRow[] = await listHabits(false);
    const cards: HabitBrief[] = [];
    for (const h of rows) {
      const doneDates: string[] = await listDoneDates(h.id, from, to);
      const streak: number = await habitStreak(h.id, day);
      const dots: boolean[] = [];
      for (const cell of week) {
        dots.push(doneDates.indexOf(cell.date) >= 0);
      }
      cards.push({
        id: h.id,
        name: h.name,
        done: doneDates.indexOf(day) >= 0,
        streak: streak,
        dots: dots
      });
    }
    this.habits = cards;

    const latest: MoodRow | null = await latestMood(day);
    this.moodLevel = latest ? latest.level : 0;

    const moods: MoodRow[] = await listMoods(from, to);
    const bars: number[] = [0, 0, 0, 0, 0, 0, 0];
    for (const m of moods) {
      const idx: number = week.findIndex((c: DayCell): boolean => c.date === m.date);
      if (idx >= 0) {
        // 同一天多条取最后一条（仓库按 date + created_at 升序返回）
        bars[idx] = m.level;
      }
    }
    this.weekMoods = bars;

    this.events = await listEventsByDate(day);
  }

  private async pickMood(level: number): Promise<void> {
    await addMood(today(), level, null, null);
    bumpRevision();
    await this.load();
  }

  /** 开关每晚回顾提醒：权限被拒或代理提醒能力没开通时给出文字引导 */
  private async setReview(on: boolean): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    if (on) {
      const ok: boolean = await enableReview(context);
      this.reviewOn = ok;
      this.reviewHint = ok ? '' : '没能开启：请允许通知，并确认已开通代理提醒能力';
    } else {
      await disableReview(context);
      this.reviewOn = false;
      this.reviewHint = '';
    }
  }

  private greeting(): string {
    const h: number = new Date().getHours();
    if (h < 11) {
      return '早安，今天想留下什么？';
    }
    if (h < 18) {
      return '午安，今天想留下什么？';
    }
    return '晚安，今天想留下什么？';
  }

  build() {
    Scroll() {
      Column() {
        // 日期行
        Row() {
          Text(todayBig())
            .fontFamily(SERIF)
            .fontSize(46)
            .fontColor(C.ink)
          Column() {
            Text(`${monthLabel()} · ${weekdayLabel()}`)
              .fontSize(11.5)
              .fontColor(C.ink2)
            Text(`${yearLabel()} 年`)
              .fontSize(11.5)
              .fontColor(C.ink3)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })

          Blank()
          SearchButton()
        }
        .width('100%')
        .padding({ top: 16 })
        .alignItems(VerticalAlign.Center)

        Text(this.greeting())
          .fontFamily(SERIF)
          .fontSize(22)
          .lineHeight(33)
          .fontColor(C.ink)
          .margin({ top: 20 })

        // 今日进度
        Row() {
          Text(`${this.stat.done}/${this.stat.total}`)
            .fontFamily(SERIF)
            .fontSize(24)
            .fontColor(C.ink)
            .margin({ right: 16 })
          Column() {
            Text('今日进度')
              .fontFamily(SERIF)
              .fontSize(15)
              .fontColor(C.ink)
            Progress({
              value: this.stat.done,
              total: this.stat.total > 0 ? this.stat.total : 1,
              type: ProgressType.Linear
            })
              .width('100%')
              .height(4)
              .color(C.cinnabar)
              .backgroundColor(C.paper3)
              .margin({ top: 8 })
            Text(`已完成 ${this.stat.done} 项，还有 ${this.stat.total - this.stat.done} 项待办`)
              .fontSize(11.5)
              .fontColor(C.ink2)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .margin({ top: 22 })

        this.todoBriefCard()
        this.habitCard()
        this.moodCard()
        this.reminderCard()

        // 今日安排
        Row() {
          Text('今日安排')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.ink2)
            .letterSpacing(2)
          Blank()
          Text('加一段 →')
            .fontSize(11)
            .fontColor(C.ink3)
            .onClick(() => openSheet('event'))
        }
        .width('100%')
        .margin({ top: 26, bottom: 14 })

        if (this.events.length === 0) {
          Column() {
            Text('今天还没有排下时间段。\n把最想专心做的那件事放进来吧。')
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
              .margin({ top: 16 })
              .onClick(() => openSheet('event'))
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
        } else {
          Column() {
            ForEach(this.events, (e: EventRow, index: number) => {
              Row() {
                Text(formatTime(e.startAt))
                  .fontSize(11)
                  .fontColor(C.ink3)
                  .width(46)
                  .align(Alignment.Start)
                Row()
                  .width(7)
                  .height(7)
                  .borderRadius(4)
                  .backgroundColor(index === 0 ? C.cinnabar : C.paper)
                  .border({ width: 1, color: index === 0 ? C.cinnabar : C.ink3 })
                  .margin({ right: 14, top: 4 })
                Column() {
                  Text(e.title)
                    .fontSize(13.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(C.ink)
                  Text(e.endAt !== null ?
                    `${formatTime(e.startAt)} – ${formatTime(e.endAt)}` : '时间待定')
                    .fontSize(11.5)
                    .fontColor(C.ink3)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ bottom: 20 })
              .alignItems(VerticalAlign.Top)
            }, (e: EventRow) => e.id)
          }
          .width('100%')
          .padding({ left: 18 })
          .border({ width: { left: 1 }, color: C.rule })
        }
      }
      .width('100%')
      .padding({
        left: S.pad, right: S.pad,
        bottom: S.contentBottom
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  todoBriefCard() {
    Column() {
      Row() {
        Text('待办 · 今天')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink2)
          .letterSpacing(2)
        Blank()
        Text(`全部 ${this.stat.total} 项 →`)
          .fontSize(10.5)
          .fontColor(C.ink3)
      }
      .width('100%')
      .padding({ bottom: 8 })

      if (this.brief.length === 0) {
        Text('今天没有待办。要不要现在加一件？')
          .fontSize(11.5)
          .fontColor(C.ink3)
          .padding({ top: 10, bottom: 14 })
      } else {
        ForEach(this.brief, (item: TodoRow) => {
          Row() {
            Row()
              .width(5)
              .height(5)
              .borderRadius(3)
              .backgroundColor(priorityColor(item.priority))
              .margin({ right: 9 })
            Text(item.title)
              .fontSize(12.5)
              .fontColor(C.ink)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(isOverdue(item.dueAt) ? '已顺延' : dueLabel(item.dueAt))
              .fontSize(9.5)
              .fontColor(isOverdue(item.dueAt) ? C.cinnabar : C.ink3)
          }
          .width('100%')
          .padding({ top: 9, bottom: 9 })
          .border({ width: { top: 1 }, color: C.ruleSoft })
        }, (item: TodoRow) => item.id)
      }
    }
    .width('100%')
    .margin({ top: 18 })
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
    .borderRadius(16)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
    .onClick(() => switchTab(2))
  }

  @Builder
  reminderCard() {
    Column() {
      Row() {
        Column() {
          Text('每晚回顾提醒')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.ink2)
            .letterSpacing(2)
          Text(`每天 ${REVIEW_HOUR}:${REVIEW_MINUTE} 提醒你记一句、收个尾`)
            .fontSize(11)
            .fontColor(C.ink3)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.reviewOn })
          .selectedColor(C.cinnabar)
          .onChange((on: boolean) => {
            this.setReview(on).catch(() => {
              this.reviewHint = '提醒设置没能保存，稍后再试';
            });
          })
      }
      .width('100%')

      if (this.reviewHint.length > 0) {
        Text(this.reviewHint)
          .fontSize(10.5)
          .fontColor(C.cinnabar)
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .margin({ top: 18 })
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(16)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
  }

  @Builder
  habitCard() {
    Column() {
      Row() {
        Text('习惯 · 今天')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink2)
          .letterSpacing(2)
        Blank()
        Text('查看全部')
          .fontSize(10.5)
          .fontColor(C.ink3)
          .onClick(() => openSub('habits'))
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.habits.length === 0) {
        Text('还没有习惯。先挑一件小事，坚持七天看看。')
          .fontSize(11.5)
          .fontColor(C.ink3)
          .padding({ top: 8, bottom: 14 })
      } else {
        ForEach(this.habits, (h: HabitBrief) => {
          Row() {
            Text(h.name)
              .fontSize(12.5)
              .fontColor(C.ink)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row() {
              ForEach(h.dots, (on: boolean, idx: number) => {
                Row()
                  .width(5)
                  .height(5)
                  .borderRadius(3)
                  .backgroundColor(on ? (idx === 6 ? C.cinnabar : C.sage) : C.paper3)
                  .margin({ right: 3 })
              }, (on: boolean, idx: number) => `${h.id}-${idx}-${on}`)
            }
            .margin({ left: 6, right: 10 })

            Text(`${h.streak} 天`)
              .fontSize(10)
              .fontColor(C.cinnabar)
              .width(44)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .border({ width: { top: 1 }, color: C.ruleSoft })
          .onClick(() => openSub('habits'))
        }, (h: HabitBrief) => h.id)
      }
    }
    .width('100%')
    .margin({ top: 22 })
    .padding({ left: 16, right: 16, top: 15, bottom: 6 })
    .borderRadius(16)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
  }

  @Builder
  moodCard() {
    Column() {
      Row() {
        Text('今天心情如何？')
          .fontFamily(SERIF)
          .fontSize(13.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink)
        Blank()
        Text('心情日记')
          .fontSize(10.5)
          .fontColor(C.ink3)
          .onClick(() => openSub('mood'))
      }
      .width('100%')
      .margin({ bottom: 13 })

      Row() {
        ForEach(MOOD_LABELS, (label: string, idx: number) => {
          Text(label)
            .fontSize(10)
            .fontColor(this.moodLevel === idx + 1 ? C.paper : C.ink2)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 9, bottom: 9 })
            .borderRadius(9)
            .backgroundColor(this.moodLevel === idx + 1 ? C.ink : C.paper2)
            .margin({ right: 6 })
            .onClick(() => this.pickMood(idx + 1))
        }, (label: string) => label)
      }
      .width('100%')

      Row() {
        ForEach(this.weekMoods, (level: number, idx: number) => {
          Column() {
            Row()
              .width('100%')
              .height(level > 0 ? level * 5 : 2)
              .borderRadius({ topLeft: 2, topRight: 2 })
              .backgroundColor(idx === 6 ? C.cinnabar : C.sage)
              .opacity(idx === 6 ? 0.78 : 0.38)
          }
          .layoutWeight(1)
          .height(28)
          .justifyContent(FlexAlign.End)
          .margin({ right: 5 })
        }, (level: number, idx: number) => `${idx}-${level}`)
      }
      .width('100%')
      .height(28)
      .margin({ top: 14 })
    }
    .width('100%')
    .margin({ top: 14 })
    .padding({ left: 16, right: 16, top: 15, bottom: 16 })
    .borderRadius(16)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
  }
}
