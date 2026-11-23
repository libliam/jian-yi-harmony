/**
 * 简忆 · 电子书阅读页（独立 @Entry，系统返回键逐层回退）
 *
 * 用 Reader Kit 的 ReadPageComponent 渲染正文：
 * 组件 readerCallback 拿到 controller → init(context) → registerBookParser(handler)
 * → setPageConfig(纸墨主题) → startPlay(spineIndex, domPos) 续读。
 * pageShow 回调记录当前章节 / DOM 位置，节流回写 book 表（进度用章节占比近似）。
 *
 * 目标 bookId 经 AppStorage 传入（READER_BOOK_KEY），与 openSub 同一套跨页参数机制。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReadPageComponent, readerCore } from '@kit.ReaderKit';
import { bookParser } from '@kit.ReaderKit';
import { C } from '../common/Theme';
import { attachUiContext } from '../common/Bus';
import { handlerFor } from '../common/BookImport';
import { getBook, updateProgress } from '../db/BookRepo';
import { BookRow } from '../db/Models';

const READER_BOOK_KEY: string = 'uiReaderBook';

/** 供列表页设置要打开的书 */
export function setReaderBook(id: string): void {
  AppStorage.setOrCreate<string>(READER_BOOK_KEY, id);
}

@Entry
@Component
struct ReaderPage {
  @State title: string = '阅读';
  @State author: string = '';
  @State loadError: string = '';
  @State ready: boolean = false;
  private controller: readerCore.ReaderComponentController =
    new readerCore.ReaderComponentController();
  private handler: bookParser.BookParserHandler | null = null;
  private book: BookRow | null = null;
  private started: boolean = false;
  private lastSaveAt: number = 0;

  async aboutToAppear(): Promise<void> {
    const id: string = AppStorage.get<string>(READER_BOOK_KEY) ?? '';
    if (id.length === 0) {
      this.loadError = '没有指定要读的书。';
      return;
    }
    try {
      this.book = await getBook(id);
      if (this.book === null) {
        this.loadError = '这本书不在书架上了。';
        return;
      }
      this.title = this.book.title;
      this.author = this.book.author ?? '佚名';
      this.handler = await handlerFor(this.book);
      if (this.handler === null) {
        this.loadError = '正文解析失败：文件可能已损坏或格式不支持。';
        return;
      }
      this.ready = true;
    } catch (err) {
      this.loadError = '打开失败，请重试。';
    }
  }

  onPageShow(): void {
    attachUiContext(this.getUIContext());
  }

  /** ReadPageComponent 初始化完成后的回调：装配控制器并续读 */
  private onReaderReady = (err: BusinessError, ctrl: readerCore.ReaderComponentController): void => {
    if (err !== undefined && err.code !== 0) {
      this.loadError = '阅读器初始化失败。';
      return;
    }
    if (this.started || this.handler === null || this.book === null) {
      return;
    }
    this.started = true;
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      // init 是异步的，但回调链里按序调用即可；Reader Kit 内部保证顺序
      ctrl.init(ctx).then(() => {
        ctrl.registerBookParser(this.handler as bookParser.BookParserHandler);
        ctrl.setPageConfig(this.pageConfig());
        const spine: number = this.book === null ? 0 : (this.book as BookRow).lastChapter;
        const domPos: string = '';
        ctrl.startPlay(spine, domPos);
        this.registerProgress(ctrl);
      }).catch(() => {
        this.started = false;
        this.loadError = '阅读器启动失败。';
      });
    } catch (e) {
      this.started = false;
      this.loadError = '阅读器启动失败。';
    }
  };

  /** 纸墨主题排版，颜色与 Theme.ets / color.json 三处对应 */
  private pageConfig(): readerCore.ReaderSetting {
    const config: readerCore.ReaderSetting = {
      fontName: 'serif',
      fontSize: 18,
      fontWeight: 400,
      fontColor: C.ink,
      fontPath: '',
      lineHeight: 1.9,
      nightMode: false,
      themeColor: C.paper,
      themeBgImg: '',
      flipMode: 'horizontal',
      scaledDensity: 1,
      viewPortWidth: 720,
      viewPortHeight: 1280
    };
    return config;
  }

  /** pageShow 回调节流写进度：章节 index + DOM 位置，章节占比近似 percent */
  private registerProgress(ctrl: readerCore.ReaderComponentController): void {
    const total: number = this.handler === null ? 0 : (this.handler as bookParser.BookParserHandler).getSpineList().length;
    ctrl.on('pageShow', (info: readerCore.PageDataInfo): void => {
      if (info.state !== readerCore.PageState.PAGE_ON_SHOW || this.book === null) {
        return;
      }
      const now: number = Date.now();
      if (now - this.lastSaveAt < 1500) {
        return; // 节流，别每翻一屏就写库
      }
      this.lastSaveAt = now;
      const chapter: number = info.resourceIndex;
      const percent: number = total > 0 ? Math.min(1, (chapter + 1) / total) : this.book.percent;
      const offset: number = info.pageOffset;
      updateProgress((this.book as BookRow).id, chapter, offset, percent).catch(() => {
        // 进度写失败不影响阅读
      });
    });
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(C.ink)
          .width(40)
          .onClick(() => this.getUIContext().getRouter().back())
        Column() {
          Text(this.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.ink)
            .maxLines(1)
          Text(this.author)
            .fontSize(10)
            .fontColor(C.ink3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })

      if (this.loadError.length > 0) {
        Column() {
          Text(this.loadError)
            .fontSize(12)
            .fontColor(C.cinnabar)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.ready) {
        ReadPageComponent({
          controller: this.controller,
          readerCallback: this.onReaderReady
        })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text('正在打开正文…')
            .fontSize(12)
            .fontColor(C.ink3)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .background(C.paper)
  }
}
