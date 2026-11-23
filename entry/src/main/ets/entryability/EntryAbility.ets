import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { initDb } from '../db/JianYiDb';
import { C } from '../common/Theme';
import { sheetFromWant, stashNotifySheet } from '../common/NotifyLaunch';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 点通知冷启动：先把目标录入类型暂存，Index 数据就绪后消费（见 NotifyLaunch.ets）
    stashNotifySheet(sheetFromWant(want));
    // 提前预热数据库连接。Index 里还会 await 一次，initDb 用同一个 Promise 保证只建表一次。
    initDb(this.context).catch(() => {
      hilog.error(DOMAIN, 'testTag', '%{public}s', 'Failed to init jianyi.db');
    });
  }

  /** 点通知热启动：Ability 已在前台/后台实例复用，Want 走这里而不是 onCreate */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    stashNotifySheet(sheetFromWant(want));
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 窗口底色 = 纸色。默认底色深色模式下是 #FF1A1A1A，会造成页面转场 / 首帧闪黑（验收标准：切深浅色不闪黑）。
    // 状态栏时间 / 电量图标用墨色，压在纸色背景上可读。
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.setWindowBackgroundColor(C.paper);
      const barProps: window.SystemBarProperties = {
        statusBarContentColor: C.ink,
        navigationBarContentColor: C.ink
      };
      win.setWindowSystemBarProperties(barProps).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set system bar props: %{public}s', JSON.stringify(err));
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to setup window: %{public}s', JSON.stringify(e));
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}