/**
 * 简忆 · 桌面卡片 UI（2*2）
 *
 * ArkTS 卡片是独立编译单元：不能 import 业务模块（Theme.ets 等），
 * 颜色一律用 $r('app.color.*') 资源引用，与 Theme.ets / color.json 三处对应。
 * 数据由 EntryFormAbility 注入，用 @LocalStorageProp 按字段名读取。
 * 整卡包一层 FormLink(router)，params.sheet 落到 want.parameters 直达待办录入。
 */

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('heading') heading: string = '简忆 · 今日';
  @LocalStorageProp('line1') line1: string = '';
  @LocalStorageProp('line2') line2: string = '';
  @LocalStorageProp('line3') line3: string = '';
  @LocalStorageProp('undone') undone: string = '';

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility',
      moduleName: 'entry',
      params: { 'sheet': 'task' }
    }) {
      Column() {
        // 抬头：朱砂点 + 标题
        Row() {
          Row()
            .width(7)
            .height(7)
            .borderRadius(4)
            .backgroundColor($r('app.color.cinnabar'))
          Text(this.heading)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .margin({ left: 6 })
        }
        .width('100%')

        // 今日前三件未完成的事
        Column() {
          if (this.line1.length > 0) {
            Text('· ' + this.line1)
              .fontSize(12)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.line2.length > 0) {
            Text('· ' + this.line2)
              .fontSize(12)
              .fontColor($r('app.color.ink_2'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.line3.length > 0) {
            Text('· ' + this.line3)
              .fontSize(12)
              .fontColor($r('app.color.ink_2'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 10 })
        .alignItems(HorizontalAlign.Start)

        // 底部状态：还有几件 / 点一下记新事
        Row() {
          Text(this.undone)
            .fontSize(11)
            .fontColor($r('app.color.cinnabar'))
          Text('点一下记新事')
            .fontSize(11)
            .fontColor($r('app.color.ink_3'))
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 'auto' })
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .backgroundColor($r('app.color.paper'))
    }
  }
}
