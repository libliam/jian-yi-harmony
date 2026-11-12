/**
 * 二级页面：习惯 / 心情 / 摘录详情
 *
 * 习惯的「连续天数」「本周达成」都是查询时现算，不落库（项目规则 3）。
 * 电子书正文属于路线图第 6 步（Reader Kit），这里只留位置说明。
 */

import { HabitRow, MoodRow, EntryRow } from '../db/Models';
import { listHabits, listDoneDates, habitStreak, checkIn } from '../db/HabitRepo';
import { latestMood, listMoods, addMood } from '../db/MoodRepo';
import { getEntry, toggleFavorite, removeEntry } from '../db/EntryRepo';
import { bumpRevision, closeSub, openSheet } from '../common/Bus';
import { C, S, SERIF, MOOD_LABELS } from '../common/Theme';
import {
  DayCell, today, currentWeek, lastSevenDays, lastNDays,
  formatDotDate, shortWeekdayOf
} from '../common/DateUtil';

interface HabitView {
  id: string;
  name: string;
  sub: string;
  done: boolean;
  streak: number;
  dots: boolean[];
}

@Component
export struct SubPages {
  @StorageLink('uiSub') @Watch('onSubChange') subPage: string = '';
  @StorageLink('uiQuoteId') quoteId: string = '';
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;

  @State habits: HabitView[] = [];
  @State heat: number[] = [];
  @State weekMoods: number[] = [0, 0, 0, 0, 0, 0, 0];
  @State moodRows: MoodRow[] = [];
  @State moodLevel: number = 0;
  @State entry: EntryRow | null = null;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onSubChange(): void {
    if (this.subPage.length > 0) {
      this.load();
    }
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.subPage === 'habits') {
      await this.loadHabits();
    } else if (this.subPage === 'mood') {
      await this.loadMoods();
    } else if (this.subPage === 'quote') {
      await this.loadQuote();
    }
  }

  private async loadHabits(): Promise<void> {
    const day: string = today();
    const week: DayCell[] = lastSevenDays();
    const from: string = week[0].date;
    const to: string = week[6].date;
    const rows: HabitRow[] = await listHabits(false);
    const views: HabitView[] = [];

    for (const h of rows) {
      const dates: string[] = await listDoneDates(h.id, from, to);
      const streak: number = await habitStreak(h.id, day);
      const dots: boolean[] = [];
      for (const cell of week) {
        dots.push(dates.indexOf(cell.date) >= 0);
      }
      const period: string = h.period === 'weekly' ? '每周' : '每天';
      const sub: string = h.remindAt ? `${period} · ${h.remindAt}` : period;
      views.push({
        id: h.id,
        name: h.name,
        sub: sub,
        done: dates.indexOf(day) >= 0,
        streak: streak,
        dots: dots
      });
    }
    this.habits = views;

    // 近 30 天热力：颜色深浅 = 当天完成的习惯数
    const days: string[] = lastNDays(30);
    const counts: number[] = [];
    for (let i: number = 0; i < days.length; i++) {
      counts.push(0);
    }
    for (const h of rows) {
      const done: string[] = await listDoneDates(h.id, days[0], days[days.length - 1]);
      for (let i: number = 0; i < days.length; i++) {
        if (done.indexOf(days[i]) >= 0) {
          counts[i] = counts[i] + 1;
        }
      }
    }
    this.heat = counts;
  }

  private async loadMoods(): Promise<void> {
    const week: DayCell[] = currentWeek();
    const from30: string = lastNDays(30)[0];
    const all: MoodRow[] = await listMoods(from30, today());
    const latest: MoodRow | null = await latestMood(today());
    this.moodLevel = latest ? latest.level : 0;

    const bars: number[] = [0, 0, 0, 0, 0, 0, 0];
    for (const m of all) {
      const idx: number = week.findIndex((c: DayCell): boolean => c.date === m.date);
      if (idx >= 0) {
        bars[idx] = m.level;
      }
    }
    this.weekMoods = bars;

    const recent: MoodRow[] = [];
    for (let i: number = all.length - 1; i >= 0 && recent.length < 8; i--) {
      recent.push(all[i]);
    }
    this.moodRows = recent;
  }

  private async loadQuote(): Promise<void> {
    this.entry = this.quoteId.length > 0 ? await getEntry(this.quoteId) : null;
  }

  private async toggleCheck(h: HabitView): Promise<void> {
    await checkIn(h.id, today(), !h.done);
    bumpRevision();
    await this.loadHabits();
  }

  private async pickMood(level: number): Promise<void> {
    await addMood(today(), level, null, null);
    bumpRevision();
    await this.loadMoods();
  }

  private async star(): Promise<void> {
    const e: EntryRow | null = this.entry;
    if (e === null) {
      return;
    }
    await toggleFavorite(e.id, e.favorite === 0);
    bumpRevision();
    await this.loadQuote();
  }

  private async remove(): Promise<void> {
    const e: EntryRow | null = this.entry;
    if (e === null) {
      return;
    }
    await removeEntry(e.id);
    bumpRevision();
    closeSub();
  }

  private doneCount(): number {
    let n: number = 0;
    for (const h of this.habits) {
      if (h.done) {
        n++;
      }
    }
    return n;
  }

  private longestStreak(): number {
    let max: number = 0;
    for (const h of this.habits) {
      if (h.streak > max) {
        max = h.streak;
      }
    }
    return max;
  }

  private weekRate(): string {
    let done: number = 0;
    for (const h of this.habits) {
      for (const on of h.dots) {
        if (on) {
          done++;
        }
      }
    }
    const total: number = this.habits.length * 7;
    if (total === 0) {
      return '0%';
    }
    return `${Math.round(done * 100 / total)}%`;
  }

  private heatColor(level: number): string {
    if (level >= 3) {
      return C.sage;
    }
    if (level === 2) {
      return '#A9B3A2';
    }
    if (level === 1) {
      return '#CDD3C7';
    }
    return C.paper3;
  }

  private title(): string {
    if (this.subPage === 'habits') {
      return '习惯';
    }
    if (this.subPage === 'mood') {
      return '心情';
    }
    if (this.subPage === 'quote') {
      return '摘录';
    }
    return '阅读';
  }

  build() {
    Column() {
      // 返回栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(20)
            .fontColor(C.ink)
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .border({ width: 1, color: C.rule })
        .justifyContent(FlexAlign.Center)
        .onClick(() => closeSub())

        Text(this.title())
          .fontFamily(SERIF)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink)
          .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 16, bottom: 18 })

      Scroll() {
        Column() {
          if (this.subPage === 'habits') {
            this.habitPage()
          } else if (this.subPage === 'mood') {
            this.moodPage()
          } else if (this.subPage === 'quote') {
            this.quotePage()
          } else {
            this.readerPage()
          }
        }
        .width('100%')
        .padding({ left: 22, right: 22, bottom: 40 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
    .zIndex(25)
  }

  @Builder
  habitPage() {
    Row() {
      this.statBox(`${this.doneCount()}/${this.habits.length}`, '今日完成')
      this.statBox(`${this.longestStreak()}`, '最长连续')
      this.statBox(this.weekRate(), '本周达成')
    }
    .width('100%')
    .padding({ bottom: 4 })

    if (this.habits.length === 0) {
      this.emptyHint('还没有习惯。\n先挑一件小事，坚持七天看看。', '新建一个习惯', 'habit')
    } else {
      ForEach(this.habits, (h: HabitView) => {
        Row() {
          Row() {
            if (h.done) {
              Text('✓').fontSize(11).fontColor(C.paper)
            }
          }
          .width(19)
          .height(19)
          .borderRadius(10)
          .border({ width: 1.4, color: h.done ? C.sage : C.ink3 })
          .backgroundColor(h.done ? C.sage : C.paper)
          .justifyContent(FlexAlign.Center)
          .margin({ right: 13 })
          .onClick(() => this.toggleCheck(h))

          Column() {
            Text(h.name)
              .fontSize(13.5)
              .fontColor(C.ink)
            Text(h.sub)
              .fontSize(10.5)
              .fontColor(C.ink3)
              .margin({ top: 5 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text(`${h.streak}`)
              .fontFamily(SERIF)
              .fontSize(16)
              .fontColor(C.cinnabar)
            Text('天连续')
              .fontSize(9)
              .fontColor(C.ink3)
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .border({ width: { bottom: 1 }, color: C.ruleSoft })
      }, (h: HabitView) => h.id)
    }

    Button('＋　新建一个习惯')
      .fontSize(12)
      .fontColor(C.ink3)
      .backgroundColor(C.paper)
      .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
      .borderRadius(14)
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .margin({ top: 16 })
      .onClick(() => openSheet('habit'))

    Text('近 30 天')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.ink2)
      .letterSpacing(2)
      .margin({ top: 26, bottom: 14 })
      .alignSelf(ItemAlign.Start)

    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.heat, (level: number, idx: number) => {
        Row()
          .width(38)
          .height(38)
          .borderRadius(3)
          .backgroundColor(this.heatColor(level))
          .margin({ right: 5, bottom: 5 })
      }, (level: number, idx: number) => `${idx}-${level}`)
    }
    .width('100%')

    Text('颜色越深，当天完成的习惯越多。空白代表没有记录。')
      .fontSize(10)
      .lineHeight(20)
      .fontColor(C.ink3)
      .margin({ top: 12 })
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  moodPage() {
    Text('Today')
      .fontSize(10)
      .fontColor(C.ink3)
      .letterSpacing(2)
      .alignSelf(ItemAlign.Start)
    Text('此刻，你感觉如何？')
      .fontFamily(SERIF)
      .fontSize(15)
      .fontColor(C.ink)
      .margin({ top: 9, bottom: 14 })
      .alignSelf(ItemAlign.Start)

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

    Text('这一周')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.ink2)
      .letterSpacing(2)
      .margin({ top: 26, bottom: 14 })
      .alignSelf(ItemAlign.Start)

    Row() {
      ForEach(this.weekMoods, (level: number, idx: number) => {
        Column() {
          Row()
            .width('100%')
            .height(level > 0 ? level * 18 : 3)
            .borderRadius({ topLeft: 3, topRight: 3 })
            .backgroundColor(idx === 6 ? C.cinnabar : C.sage)
            .opacity(idx === 6 ? 0.8 : 0.42)
          Text(['一', '二', '三', '四', '五', '六', '日'][idx])
            .fontSize(9.5)
            .fontColor(idx === 6 ? C.cinnabar : C.ink3)
            .margin({ top: 7 })
        }
        .layoutWeight(1)
        .height(112)
        .justifyContent(FlexAlign.End)
        .margin({ right: 9 })
      }, (level: number, idx: number) => `${idx}-${level}`)
    }
    .width('100%')

    Text('最近记录')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.ink2)
      .letterSpacing(2)
      .margin({ top: 22, bottom: 8 })
      .alignSelf(ItemAlign.Start)

    if (this.moodRows.length === 0) {
      this.emptyHint('还没有心情记录。\n今天挑一个词，就是一条开始。', '记录此刻', 'mood')
    } else {
      ForEach(this.moodRows, (m: MoodRow) => {
        Row() {
          Text(`${m.date.substring(5).replace('-', '.')}\n${shortWeekdayOf(m.date)}`)
            .fontSize(10)
            .lineHeight(16)
            .fontColor(C.ink3)
            .width(44)
          Column() {
            Text(m.note ? m.note : '只记下了心情')
              .fontSize(12.5)
              .fontColor(C.ink)
            Text(m.note ? '' : '没有写别的话')
              .fontSize(11)
              .fontColor(C.ink3)
              .margin({ top: 5 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(MOOD_LABELS[m.level - 1])
            .fontSize(9.5)
            .fontColor(C.sage)
            .border({ width: 1, color: C.rule })
            .borderRadius(3)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        .width('100%')
        .padding({ top: 15, bottom: 15 })
        .border({ width: { bottom: 1 }, color: C.ruleSoft })
        .alignItems(VerticalAlign.Top)
      }, (m: MoodRow) => m.id)
    }

    Button('＋　记录此刻')
      .fontSize(12)
      .fontColor(C.ink3)
      .backgroundColor(C.paper)
      .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
      .borderRadius(14)
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .margin({ top: 18 })
      .onClick(() => openSheet('mood'))
  }

  private entryContent(): string {
    const e: EntryRow | null = this.entry;
    return e === null ? '' : e.content;
  }

  private quoteSrc(): string {
    const e: EntryRow | null = this.entry;
    return e === null || e.source === null ? '' : e.source;
  }

  private quoteTags(): string {
    const e: EntryRow | null = this.entry;
    return e === null || e.tags === null ? '' : e.tags;
  }

  private entryFavorite(): number {
    const e: EntryRow | null = this.entry;
    return e === null ? 0 : e.favorite;
  }

  private entryCreatedAt(): number {
    const e: EntryRow | null = this.entry;
    return e === null ? 0 : e.createdAt;
  }

  @Builder
  quotePage() {
    if (this.entry === null) {
      this.emptyHint('这条摘录已经不在了。\n回到语录页，再记一句吧。', '', '')
    } else {
      Text('“')
        .fontFamily(SERIF)
        .fontSize(46)
        .fontColor(C.cinnabar)
        .opacity(0.3)
        .alignSelf(ItemAlign.Start)
      Text(this.entryContent())
        .fontFamily(SERIF)
        .fontSize(19)
        .lineHeight(39)
        .fontColor(C.ink)
        .textAlign(TextAlign.JUSTIFY)
        .margin({ top: 16, bottom: 22 })
      if (this.quoteSrc().length > 0) {
        Text(this.quoteSrc())
          .fontSize(11.5)
          .fontColor(C.ink3)
          .alignSelf(ItemAlign.Start)
      }
      if (this.quoteTags().length > 0) {
        Row() {
          ForEach(this.quoteTags().split(',').filter((t: string): boolean => t.length > 0),
            (tag: string) => {
              Text(tag)
                .fontSize(9.5)
                .fontColor(C.sage)
                .border({ width: 1, color: C.rule })
                .borderRadius(3)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ right: 7 })
            }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ top: 16 })
      }
      Text(`记于 ${formatDotDate(this.entryCreatedAt())} · 已归档 · 未同步`)
        .fontSize(10)
        .fontColor(C.ink3)
        .margin({ top: 24 })
        .alignSelf(ItemAlign.Start)

      Row() {
        Button(this.entryFavorite() === 1 ? '★ 已收藏' : '☆ 收藏')
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.entryFavorite() === 1 ? C.cinnabar : C.ink2)
          .backgroundColor(C.paper)
          .border({ width: 1, color: C.rule })
          .borderRadius(S.smallRadius)
          .padding({ top: 13, bottom: 13 })
          .onClick(() => this.star())
        Button('删除')
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(C.cinnabar)
          .backgroundColor(C.paper)
          .border({ width: 1, color: C.rule })
          .borderRadius(S.smallRadius)
          .padding({ top: 13, bottom: 13 })
          .margin({ left: 10 })
          .onClick(() => this.remove())
      }
      .width('100%')
      .margin({ top: 26 })
    }
  }

  @Builder
  readerPage() {
    Column() {
      Text('阅读器')
        .fontFamily(SERIF)
        .fontSize(20)
        .fontColor(C.ink)
      Text('电子书正文解析属于路线图第 6 步，需要 Reader Kit 与真机调试。\n书架和阅读进度已经接上数据库，可以先在「阅读」页查看。')
        .fontSize(11.5)
        .lineHeight(22)
        .fontColor(C.ink3)
        .textAlign(TextAlign.Center)
        .margin({ top: 14 })
    }
    .width('100%')
    .padding({ top: 60 })
  }

  @Builder
  statBox(value: string, label: string) {
    Column() {
      Text(value)
        .fontFamily(SERIF)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.ink)
      Text(label)
        .fontSize(11)
        .fontColor(C.ink3)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ right: 22 })
  }

  @Builder
  emptyHint(text: string, action: string, sheet: string) {
    Column() {
      Text(text)
        .fontSize(11.5)
        .lineHeight(22)
        .fontColor(C.ink3)
        .textAlign(TextAlign.Center)
      if (sheet.length > 0) {
        Button(action)
          .fontSize(11)
          .fontColor(C.ink2)
          .backgroundColor(C.paper)
          .border({ width: 1, color: C.rule })
          .borderRadius(S.pill)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .margin({ top: 18 })
          .onClick(() => openSheet(sheet))
      }
    }
    .width('100%')
    .padding({ top: 30, bottom: 30 })
  }
}
