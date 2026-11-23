/**
 * 简忆 · 锁屏页（独立 @Entry，走系统页面栈）
 *
 * 由 Index 在「应用锁开启 + 需要重新验证」时 push 进来。
 * - 系统返回键 / 侧滑返回被 onBackPress 吞掉，认证成功前退不到主界面；
 * - 点击「解锁」拉起系统原生人脸 / 指纹弹窗（见 AppLock.authenticate）；
 * - 认证成功 unlock() 后 router.back() 回到 Index。
 *
 * 纸墨风格，色值从 Theme 取（项目规则 5）。
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authenticate, unlock } from '../common/AppLock';
import { onLockGone, onLockShown } from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';

@Entry
@Component
struct LockPage {
  @State hint: string = '轻触下方按钮，用指纹或面容解锁简忆';
  @State busy: boolean = false;

  aboutToAppear(): void {
    onLockShown();
  }

  aboutToDisappear(): void {
    onLockGone();
  }

  /** 吞掉系统返回键：锁屏状态下不能靠返回绕过去 */
  onBackPress(): boolean {
    return true;
  }

  private doUnlock(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ctx: common.Context = getContext(this) as common.Context;
    authenticate(
      ctx,
      () => {
        unlock();
        router.back();
      },
      (code: number) => {
        this.busy = false;
        if (code === 12500003) {
          this.hint = '已取消解锁，再试一次';
        } else if (code === 12500009) {
          this.hint = '验证次数过多已锁定，请稍后再试';
        } else if (code === 12500010) {
          this.hint = '还没有录入指纹或面容，请先在系统设置里添加';
        } else {
          this.hint = '没能识别，请用指纹或面容再试一次';
        }
      }
    );
  }

  build() {
    Column() {
      Column() {
        Text('简')
          .fontSize(46)
          .fontFamily(SERIF)
          .fontColor(C.paper)
          .width(72)
          .height(72)
          .textAlign(TextAlign.Center)
          .backgroundColor(C.ink)
          .borderRadius(S.cardRadius)
      }
      .margin({ bottom: 34 })

      Text('简忆已上锁')
        .fontSize(22)
        .fontFamily(SERIF)
        .fontColor(C.ink)
        .margin({ bottom: 10 })

      Text('你的记录只属于你。')
        .fontSize(13)
        .fontColor(C.ink3)
        .margin({ bottom: 54 })

      Text(this.hint)
        .fontSize(12)
        .fontColor(C.ink2)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 22 })
        .padding({ left: 32, right: 32 })

      Button('解锁')
        .fontSize(15)
        .fontColor(C.paper)
        .backgroundColor(C.ink)
        .borderRadius(S.pill)
        .width(200)
        .height(46)
        .enabled(!this.busy)
        .onClick(() => this.doUnlock())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
