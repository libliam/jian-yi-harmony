/**
 * 阅读页
 *
 * 书架与阅读进度已经落到 book 表；正文解析属于路线图第 6 步（Reader Kit）。
 * 仓库层不碰文件系统（项目规则 4），所以这里也不做导入文件。
 */

import { common } from '@kit.AbilityKit';
import { BookRow } from '../db/Models';
import { listBooks, currentReading } from '../db/BookRepo';
import { bumpRevision } from '../common/Bus';
import { openReaderPage } from '../common/Bus';
import { setReaderBook } from '../pages/ReaderPage';
import { importLocalBook } from '../common/BookImport';
import { C, S, SERIF } from '../common/Theme';
import { PageHead } from './Parts';

const COVERS: string[] = ['#3E5647', '#8C4A34', '#3C4657', '#B08A4A', '#5A5B6B'];

@Component
export struct ReaderView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State books: BookRow[] = [];
  @State current: BookRow | null = null;
  @State hint: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.books = await listBooks();
    this.current = await currentReading();
  }

  private readingCount(): number {
    let n: number = 0;
    for (const b of this.books) {
      if (b.percent > 0 && b.percent < 1) {
        n++;
      }
    }
    return n;
  }

  private coverColor(index: number): string {
    return COVERS[index % COVERS.length];
  }

  private percentText(b: BookRow): string {
    if (b.percent <= 0) {
      return '未开始';
    }
    return `已读 ${Math.round(b.percent * 100)}%`;
  }

  private currentTitle(): string {
    const c: BookRow | null = this.current;
    return c === null ? '' : c.title;
  }

  private currentAuthor(): string {
    const c: BookRow | null = this.current;
    return c !== null && c.author !== null && c.author.length > 0 ? c.author : '佚名';
  }

  private currentPercent(): number {
    const c: BookRow | null = this.current;
    return c === null ? 0 : c.percent;
  }

  private currentTotalPages(): number {
    const c: BookRow | null = this.current;
    return c === null ? 0 : c.totalPages;
  }

  /** 打开某本书：先写跨页参数，再压入系统页面栈 */
  private openBook(b: BookRow): void {
    setReaderBook(b.id);
    openReaderPage();
  }

  /** 导入本地电子书：picker → 复制到沙箱 → 解析入库 → 刷新书架 */
  private async importBook(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await importLocalBook(ctx);
      if (result === null) {
        this.hint = '没有导入书，或这本的格式暂时读不了（支持 epub / txt / pdf / mobi）。';
        return;
      }
      this.hint = `已加入书架：《${result.title}》`;
      bumpRevision();
      await this.load();
    } catch (err) {
      this.hint = '导入失败，请确认文件格式后重试。';
    }
  }

  @Builder
  readingCard() {
    if (this.current !== null) {
      Row() {
        Column() {
          Text(this.currentTitle())
            .fontFamily(SERIF)
            .fontSize(12)
            .fontColor(C.white)
            .maxLines(4)
            .textAlign(TextAlign.Center)
        }
        .width(78)
        .height(112)
        .borderRadius(4)
        .backgroundColor(this.coverColor(0))
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('继续阅读')
            .fontSize(10)
            .fontColor(C.cinnabar)
            .letterSpacing(2)
          Text(this.currentTitle())
            .fontFamily(SERIF)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.ink)
            .margin({ top: 7 })
          Text(this.currentAuthor())
            .fontSize(11)
            .fontColor(C.ink3)
            .margin({ top: 4 })

          Row() {
            Row()
              .width(`${Math.round(this.currentPercent() * 100)}%`)
              .height(2)
              .backgroundColor(C.cinnabar)
          }
          .width('100%')
          .height(2)
          .borderRadius(2)
          .backgroundColor(C.paper3)
          .margin({ top: 14 })

          Row() {
            Text(`第 ${Math.round(this.currentPercent() * this.currentTotalPages())} 页 / ${this.currentTotalPages()}`)
              .fontSize(10)
              .fontColor(C.ink3)
            Blank()
            Text(`${Math.round(this.currentPercent() * 100)}%`)
              .fontSize(10)
              .fontColor(C.ink3)
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18 })
      }
      .width('100%')
      .padding(18)
      .borderRadius(S.cardRadius)
      .backgroundColor(C.paper2)
      .margin({ bottom: 26 })
      .onClick(() => {
        const c: BookRow | null = this.current;
        if (c !== null) {
          this.openBook(c as BookRow);
        }
      })
    }
  }

  build() {
    Column() {
      PageHead({ eyebrow: 'Reading', title: '阅读', meta: `${this.readingCount()} 在读` })

      Scroll() {
        Column() {
          this.readingCard()

          Row() {
            Text('我的书架')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.ink2)
              .letterSpacing(2)
            Blank()
            Text(`${this.books.length} 本`)
              .fontSize(10.5)
              .fontColor(C.ink3)
          }
          .width('100%')
          .margin({ bottom: 14 })

          if (this.books.length === 0) {
            Column() {
              Text('书架还空着。\n导入一本本地电子书，就能在这里续读。')
                .fontSize(11.5)
                .lineHeight(22)
                .fontColor(C.ink3)
                .textAlign(TextAlign.Center)
              Button('导入第一本书')
                .fontSize(11)
                .fontColor(C.ink2)
                .backgroundColor(C.paper)
                .border({ width: 1, color: C.rule })
                .borderRadius(S.pill)
                .padding({ left: 18, right: 18, top: 9, bottom: 9 })
                .margin({ top: 18 })
                .onClick(() => this.importBook())
            }
            .width('100%')
            .padding({ top: 30, bottom: 30 })
          } else {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.books, (b: BookRow, index: number) => {
                Row() {
                  Column() {
                    Text(b.title)
                      .fontFamily(SERIF)
                      .fontSize(10)
                      .fontColor(C.white)
                      .maxLines(4)
                      .textAlign(TextAlign.Center)
                  }
                  .width(52)
                  .height(74)
                  .borderRadius(3)
                  .backgroundColor(this.coverColor(index + 1))
                  .justifyContent(FlexAlign.Center)

                  Column() {
                    Text(b.title)
                      .fontFamily(SERIF)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(C.ink)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(b.author ? b.author : '佚名')
                      .fontSize(9.5)
                      .fontColor(C.ink3)
                      .margin({ top: 5 })
                    Text(this.percentText(b))
                      .fontSize(9.5)
                      .fontColor(C.sage)
                      .margin({ top: 7 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 12 })
                }
                .width('48%')
                .margin({ bottom: 14 })
                .alignItems(VerticalAlign.Top)
                .onClick(() => this.openBook(b))
              }, (b: BookRow) => b.id)
            }
            .width('100%')
          }

          Button('＋　导入本地电子书')
            .fontSize(12)
            .fontColor(C.ink3)
            .backgroundColor(C.paper)
            .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
            .borderRadius(14)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .margin({ top: 4 })
            .onClick(() => this.importBook())

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(10.5)
              .lineHeight(20)
              .fontColor(C.cinnabar)
              .margin({ top: 12 })
          }
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
}
