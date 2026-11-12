/**
 * 五个视图共用的小部件
 *
 * 空态必须给「下一步做什么」（项目规则 5），所以 EmptyState 自带一个
 * 直接打开录入弹层的按钮，不允许只写「暂无数据」。
 */

import { openSearch, openSheet } from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';

@Component
export struct SearchButton {
  build() {
    Row() {
      Text('搜')
        .fontSize(11)
        .fontColor(C.ink2)
        .fontFamily(SERIF)
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .border({ width: 1, color: C.rule })
    .justifyContent(FlexAlign.Center)
    .onClick(() => openSearch())
  }
}

@Component
export struct PageHead {
  @Prop eyebrow: string = '';
  @Prop title: string = '';
  @Prop meta: string = '';

  build() {
    Row() {
      Column() {
        Text(this.eyebrow)
          .fontSize(10.5)
          .fontColor(C.ink3)
          .letterSpacing(2)
        Text(this.title)
          .fontFamily(SERIF)
          .fontSize(31)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (this.meta.length > 0) {
        Text(this.meta)
          .fontSize(11)
          .fontColor(C.ink3)
          .margin({ right: 10 })
      }
      SearchButton()
    }
    .width('100%')
    .padding({ top: 14, bottom: 16 })
    .alignItems(VerticalAlign.Bottom)
  }
}

@Component
export struct EmptyState {
  @Prop mark: string = '“';
  @Prop text: string = '这里还空着。';
  @Prop action: string = '记一条';
  @Prop sheet: string = '';

  build() {
    Column() {
      Text(this.mark)
        .fontFamily(SERIF)
        .fontSize(32)
        .fontColor(C.ink3)
        .opacity(0.5)
      Text(this.text)
        .fontSize(11.5)
        .lineHeight(22)
        .fontColor(C.ink3)
        .textAlign(TextAlign.Center)
        .margin({ top: 14 })
      if (this.sheet.length > 0) {
        Button(this.action)
          .fontSize(11)
          .fontColor(C.ink2)
          .backgroundColor(C.paper)
          .border({ width: 1, color: C.rule })
          .borderRadius(S.pill)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .margin({ top: 18 })
          .onClick(() => openSheet(this.sheet))
      }
    }
    .width('100%')
    .padding({ top: 40, bottom: 34 })
  }
}
