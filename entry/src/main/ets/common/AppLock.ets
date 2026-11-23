/**
 * 简忆 · 应用锁
 *
 * 用系统 userAuth 拉起原生人脸 / 指纹认证（不是自绘假锁）。
 * 两块状态：
 * - 开关「是否启用应用锁」落 Preferences，重启仍在；
 * - 「当前是否已锁」落 AppStorage('appLocked')，页面与 Ability 共享同一份，
 *   LockPage 认证成功后清掉，Index 才可交互。
 *
 * 触发时机（遵循系统生命周期，不用自绘按钮糊弄）：
 * - Ability 退回后台 → 立即置锁；
 * - Ability 回前台 / 冷启动 → 若开关开着，页面停在 LockPage；
 * - 系统返回键在 LockPage 被吞掉，认证成功前退不出去。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';

const PREF_NAME: string = 'jianyi_meta';
const LOCK_ENABLED_KEY: string = 'app_lock_enabled';

/** 应用锁是否已开启（Preferences，跨重启） */
export async function isLockEnabled(context: common.Context): Promise<boolean> {
  const opts: preferences.Options = { name: PREF_NAME };
  const p: preferences.Preferences = await preferences.getPreferences(context, opts);
  return p.getSync(LOCK_ENABLED_KEY, false) === true;
}

/** 开启 / 关闭应用锁。关闭时顺带解锁，避免下次进来卡在锁屏 */
export async function setLockEnabled(context: common.Context, enabled: boolean): Promise<void> {
  const opts: preferences.Options = { name: PREF_NAME };
  const p: preferences.Preferences = await preferences.getPreferences(context, opts);
  await p.put(LOCK_ENABLED_KEY, enabled);
  await p.flush();
  if (!enabled) {
    unlock();
  }
}

/** 当前是否处于锁定状态（AppStorage，页面与 Ability 共享） */
export function isLocked(): boolean {
  return AppStorage.get<boolean>('appLocked') === true;
}

export function lock(): void {
  AppStorage.setOrCreate<boolean>('appLocked', true);
}

export function unlock(): void {
  AppStorage.setOrCreate<boolean>('appLocked', false);
}

/**
 * 设备是否录入了可用的人脸 / 指纹（开启开关前先探测，给提示用）。
 * 注意：getAvailableStatus 返回 void，靠抛异常表示不可用（12500010 = 未录入），
 * 所以「调用不抛异常」即代表该方式可用。
 */
export function hasBiometric(): boolean {
  const atl: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2;
  try {
    userAuth.getAvailableStatus(userAuth.UserAuthType.FACE, atl);
    return true;
  } catch (err) {
    // 人脸不可用，再看指纹
  }
  try {
    userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, atl);
    return true;
  } catch (err) {
    return false;
  }
}

/**
 * 拉起系统生物识别。认证结果通过回调返回：
 * - SUCCESS：调用方应 unlock() 并离开锁屏页；
 * - 其它：保持锁定，用户可重试。
 *
 * 每次调用都新建 instance（系统规定一个 instance 只能用一次）。
 */
export function authenticate(
  uiContext: common.Context,
  onSuccess: () => void,
  onFail: (code: number) => void
): void {
  let instance: userAuth.UserAuthInstance | null = null;
  try {
    const challenge: Uint8Array = new Uint8Array(16);
    // 简易随机 challenge：每次认证不同即可，防止重放
    for (let i: number = 0; i < challenge.length; i++) {
      challenge[i] = Math.floor(Math.random() * 256);
    }
    const authParam: userAuth.AuthParam = {
      challenge: challenge,
      authType: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
      authTrustLevel: userAuth.AuthTrustLevel.ATL2
    };
    const widgetParam: userAuth.WidgetParam = { title: '简忆 · 解锁' };
    instance = userAuth.getUserAuthInstance(authParam, widgetParam);
    instance.on('result', {
      onResult(result: userAuth.UserAuthResult): void {
        if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
          onSuccess();
        } else {
          onFail(result.result);
        }
      }
    });
    instance.start();
  } catch (err) {
    const e = err as BusinessError;
    onFail(e.code);
  }
}
