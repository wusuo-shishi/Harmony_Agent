import { deviceInfo } from '@kit.BasicServicesKit';

export class CapabilityManager {
  static isEmulator(): boolean {
    return deviceInfo.productModel === 'emulator';
  }

  static deviceType(): string {
    return deviceInfo.deviceType;
  }

  static isLargeScreenDevice(): boolean {
    return deviceInfo.deviceType !== 'phone';
  }

  static supportsDataAugmentationKit(): boolean {
    return !CapabilityManager.isEmulator();
  }

  static supportsRealtimeAsr(): boolean {
    return !CapabilityManager.isEmulator();
  }

  static supportsCalendar(): boolean {
    return !CapabilityManager.isEmulator();
  }
}
