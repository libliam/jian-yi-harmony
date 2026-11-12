/**
 * 快速记录弹层
 *
 * 原型里保存按钮只是关掉弹层；这里是真写库。
 * 每种表单保存成功后 bumpRevision()，五个视图自动重拉数据。
 */

import { addEntry } from '../db/EntryRepo';
import { addTodo } from '../db/TodoRepo';
import { addThought } from '../db/ThoughtRepo';
import { addMood } from '../db/MoodRepo';
import { addHabit } from '../db/HabitRepo';
import { addEvent } from '../db/EventRepo';
import { EntryType, TodoBucket, Priority, HabitPeriod } from '../db/Models';
import { bumpRevision, closeSheet, openSheet } from '../common/Bus';
import { C, S, SERIF, MOOD_LABELS } from '../common/Theme';
import { today, atToday, atDay } from '../common/DateUtil';

const QUOTE_TYPES: string[] = ['语录', '剪藏', '手记'];
const TAG_OPTIONS: string[] = ['哲思', '写作', '生活', '工作'];
const BUCKET_OPTIONS: string[] = ['今天', '长期'];
const PRIORITY_OPTIONS: string[] = ['低', '中', '高'];
const PERIOD_OPTIONS: string[] = ['每天', '每周'];
const TIME_OPTIONS: string[] = ['08:30', '09:30', '14:30', '20:30'];

@Component
export struct QuickSheet {
  @StorageLink('uiSheet') @Watch('onSheetChange') sheetType: string = '';
  @StorageLink('uiTodoPane') pane: string = 'today';
  @StorageLink('uiPlanDate') planDate: string = '';

  @State content: string = '';
  @State source: string = '';
  @State url: string = '';
  @State entryType: string = '语录';
  @State tag: string = '哲思';
  @State bucket: string = '今天';
  @State priority: string = '中';
  @State mood: string = '平静';
  @State period: string = '每天';
  @State time: string = '09:30';
  @State tip: string = '';

  onSheetChange(): void {
    if (this.sheetType.length > 0) {
      this.reset();
    }
  }

  private reset(): void {
    this.content = '';
    this.source = '';
    this.url = '';
    this.entryType = '语录';
    this.tag = '哲思';
    this.bucket = this.pane === 'later' ? '长期' : '今天';
    this.priority = '中';
    this.mood = '平静';
    this.period = '每天';
    this.time = '09:30';
    this.tip = '';
  }

  private pick(kind: string, value: string): void {
    if (kind === 'type') {
      this.entryType = value;
    } else if (kind === 'tag') {
      this.tag = value;
    } else if (kind === 'bucket') {
      this.bucket = value;
    } else if (kind === 'priority') {
      this.priority = value;
    } else if (kind === 'mood') {
      this.mood = value;
    } else if (kind === 'period') {
      this.period = value;
    } else if (kind === 'time') {
      this.time = value;
    }
  }

  private async save(): Promise<void> {
    const text: string = this.content.trim();
    if (text.length === 0) {
      this.tip = '先写点什么吧，一句话也算。';
      return;
    }

    if (this.sheetType === 'quote') {
      let type: EntryType = EntryType.Quote;
      if (this.entryType === '剪藏') {
        type = EntryType.Snippet;
      } else if (this.entryType === '手记') {
        type = EntryType.Note;
      }
      await addEntry(type, text,
        this.source.trim().length > 0 ? this.source.trim() : null,
        this.url.trim().length > 0 ? this.url.trim() : null,
        this.tag);
    } else if (this.sheetType === 'task') {
      const b: TodoBucket = this.bucket === '长期' ? TodoBucket.Later : TodoBucket.Today;
      let p: Priority = Priority.Mid;
      if (this.priority === '高') {
        p = Priority.High;
      } else if (this.priority === '低') {
        p = Priority.Low;
      }
      // 今天的待办给一个当天截止时间，长期清单不设截止时间
      await addTodo(text, b, p, b === TodoBucket.Today ? atToday(18, 0) : null, null);
    } else if (this.sheetType === 'think') {
      await addThought(text);
    } else if (this.sheetType === 'mood') {
      const idx: number = MOOD_LABELS.indexOf(this.mood);
      await addMood(today(), idx >= 0 ? idx + 1 : 3, text, null);
    } else if (this.sheetType === 'habit') {
      await addHabit(text,
        this.period === '每周' ? HabitPeriod.Weekly : HabitPeriod.Daily,
        7, this.time);
    } else if (this.sheetType === 'event') {
      const parts: string[] = this.time.split(':');
      const date: string = this.planDate.length > 0 ? this.planDate : today();
      await addEvent(text, date,
        atDay(date, Number(parts[0]), Number(parts[1])), null, 'local');
    }

    bumpRevision();
    closeSheet();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#661B1917')
        .onClick(() => closeSheet())

      Column() {
        Row()
          .width(34)
          .height(4)
          .borderRadius(2)
          .backgroundColor(C.paper3)
          .margin({ top: 2, bottom: 18 })

        if (this.sheetType === 'more') {
          this.morePane()
        } else {
          this.formPane()
        }
      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 26 })
      .borderRadius({ topLeft: 24, topRight: 24 })
      .backgroundColor(C.paper)
      .constraintSize({ maxHeight: '80%' })
    }
    .width('100%')
    .height('100%')
    .zIndex(40)
  }

  @Builder
  morePane() {
    Text('快速记录')
      .fontFamily(SERIF)
      .fontSize(19)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.ink)
    Text('想到什么先记下来，之后再慢慢整理')
      .fontSize(10.5)
      .fontColor(C.ink3)
      .margin({ top: 6, bottom: 18 })

    Column() {
      Row() {
        this.quickItem('记一句话', '语录 · 摘抄 · 剪藏', 'quote')
        this.quickItem('加个待办', '今天做，还是长期', 'task')
      }
      .width('100%')
      Row() {
        this.quickItem('存个想法', '待思清单', 'think')
        this.quickItem('记下心情', '一句话就够', 'mood')
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
  }

  @Builder
  quickItem(title: string, sub: string, target: string) {
    Column() {
      Text(title)
        .fontFamily(SERIF)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.ink)
      Text(sub)
        .fontSize(10)
        .fontColor(C.ink3)
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .padding({ left: 14, right: 14, top: 16, bottom: 16 })
    .margin({ right: 10 })
    .borderRadius(14)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => openSheet(target))
  }

  @Builder
  formPane() {
    Text(this.titleOf())
      .fontFamily(SERIF)
      .fontSize(19)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.ink)
    Text(this.subOf())
      .fontSize(10.5)
      .fontColor(C.ink3)
      .margin({ top: 6, bottom: 18 })

    if (this.sheetType === 'quote') {
      this.fieldLabel('类型')
      this.miniChips(QUOTE_TYPES, this.entryType, 'type')
    }

    if (this.sheetType === 'task') {
      this.fieldLabel('什么时候')
      this.miniChips(BUCKET_OPTIONS, this.bucket, 'bucket')
      this.fieldLabel('重要程度')
      this.miniChips(PRIORITY_OPTIONS, this.priority, 'priority')
    }

    if (this.sheetType === 'mood') {
      this.fieldLabel('心情')
      this.miniChips(MOOD_LABELS, this.mood, 'mood')
    }

    if (this.sheetType === 'habit') {
      this.fieldLabel('频率')
      this.miniChips(PERIOD_OPTIONS, this.period, 'period')
      this.fieldLabel('提醒时间')
      this.miniChips(TIME_OPTIONS, this.time, 'time')
    }

    if (this.sheetType === 'event') {
      this.fieldLabel('时间')
      this.miniChips(TIME_OPTIONS, this.time, 'time')
    }

    this.fieldLabel(this.sheetType === 'habit' ? '习惯名称' :
      this.sheetType === 'event' ? '安排什么' : this.sheetType === 'task' ? '要做的事' : '内容')

    if (this.sheetType === 'quote' || this.sheetType === 'think' || this.sheetType === 'mood') {
      TextArea({ placeholder: this.placeholderOf(), text: this.content })
        .width('100%')
        .height(76)
        .fontSize(13.5)
        .fontColor(C.ink)
        .backgroundColor(C.paper)
        .border({ width: { bottom: 1 }, color: C.rule })
        .onChange((value: string) => {
          this.content = value;
          this.tip = '';
        })
    } else {
      TextInput({ placeholder: this.placeholderOf(), text: this.content })
        .width('100%')
        .fontSize(13.5)
        .fontColor(C.ink)
        .backgroundColor(C.paper)
        .border({ width: { bottom: 1 }, color: C.rule })
        .padding({ top: 8, bottom: 10 })
        .onChange((value: string) => {
          this.content = value;
          this.tip = '';
        })
    }

    if (this.sheetType === 'quote') {
      if (this.entryType === '剪藏') {
        this.fieldLabel('原文链接')
        TextInput({ placeholder: '粘贴链接', text: this.url })
          .width('100%')
          .fontSize(13.5)
          .fontColor(C.ink)
          .backgroundColor(C.paper)
          .border({ width: { bottom: 1 }, color: C.rule })
          .padding({ top: 8, bottom: 10 })
          .onChange((value: string) => {
            this.url = value;
          })
      } else {
        this.fieldLabel('出处')
        TextInput({ placeholder: '作者 / 书名，可留空', text: this.source })
          .width('100%')
          .fontSize(13.5)
          .fontColor(C.ink)
          .backgroundColor(C.paper)
          .border({ width: { bottom: 1 }, color: C.rule })
          .padding({ top: 8, bottom: 10 })
          .onChange((value: string) => {
            this.source = value;
          })
      }
      this.fieldLabel('标签')
      this.miniChips(TAG_OPTIONS, this.tag, 'tag')
    }

    if (this.tip.length > 0) {
      Text(this.tip)
        .fontSize(11)
        .fontColor(C.cinnabar)
        .margin({ top: 12 })
    }

    Row() {
      Button('取消')
        .layoutWeight(1)
        .fontSize(12)
        .fontColor(C.ink2)
        .backgroundColor(C.paper)
        .border({ width: 1, color: C.rule })
        .borderRadius(S.smallRadius)
        .padding({ top: 13, bottom: 13 })
        .onClick(() => closeSheet())

      Button(this.sheetType === 'task' ? '加上' :
        this.sheetType === 'think' ? '存下' :
          this.sheetType === 'mood' ? '记下' :
            this.sheetType === 'habit' ? '创建' : '保存')
        .layoutWeight(1)
        .fontSize(12)
        .fontColor(C.paper)
        .backgroundColor(C.ink)
        .borderRadius(S.smallRadius)
        .padding({ top: 13, bottom: 13 })
        .margin({ left: 10 })
        .onClick(() => this.save())
    }
    .width('100%')
    .margin({ top: 22 })
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(9.5)
      .fontColor(C.ink3)
      .letterSpacing(2)
      .margin({ top: 16, bottom: 7 })
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  miniChips(options: string[], current: string, kind: string) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(options, (opt: string) => {
        Text(opt)
          .fontSize(10.5)
          .fontColor(current === opt ? C.paper : C.ink2)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(S.pill)
          .border({ width: 1, color: current === opt ? C.ink : C.rule })
          .backgroundColor(current === opt ? C.ink : C.paper)
          .margin({ right: 7, bottom: 7 })
          .onClick(() => this.pick(kind, opt))
      }, (opt: string) => kind + opt)
    }
    .width('100%')
  }

  private titleOf(): string {
    if (this.sheetType === 'quote') {
      return '记下一点东西';
    }
    if (this.sheetType === 'task') {
      return '新建待办';
    }
    if (this.sheetType === 'think') {
      return '存个想法';
    }
    if (this.sheetType === 'mood') {
      return '记录此刻';
    }
    if (this.sheetType === 'habit') {
      return '新建习惯';
    }
    return '加一段安排';
  }

  private subOf(): string {
    if (this.sheetType === 'quote') {
      return '语录、灵感，或者从别处剪藏的一段';
    }
    if (this.sheetType === 'task') {
      return '记下来，就不必一直放在脑子里';
    }
    if (this.sheetType === 'think') {
      return '不急着想清楚，先放进待思，之后再来想';
    }
    if (this.sheetType === 'mood') {
      return '不用写得完整，一句话就够了';
    }
    if (this.sheetType === 'habit') {
      return '从小处开始，先坚持七天';
    }
    return '把这段时间留给它';
  }

  private placeholderOf(): string {
    if (this.sheetType === 'quote') {
      return '写下一句话……';
    }
    if (this.sheetType === 'task') {
      return '比如：把评审材料的结论补完';
    }
    if (this.sheetType === 'think') {
      return '比如：阅读笔记要不要做成双链？';
    }
    if (this.sheetType === 'mood') {
      return '现在发生了什么？';
    }
    if (this.sheetType === 'habit') {
      return '比如：睡前读十页书';
    }
    return '比如：产品评审会';
  }
}
