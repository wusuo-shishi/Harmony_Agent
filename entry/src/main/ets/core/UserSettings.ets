import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LlmConfig } from '../provider/llm/LlmConfig';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';

export class UserSettings {
  static agenticEnabled: boolean = false;
  static retrievalTopK: number = 3;
  private static pref: preferences.Preferences | undefined = undefined;

  static async load(ctx: common.UIAbilityContext): Promise<void> {
    UserSettings.pref = await preferences.getPreferences(ctx, { name: 'user_settings' });
    UserSettings.agenticEnabled = await UserSettings.pref.get('agentic_enabled', false) as boolean;
    UserSettings.retrievalTopK = await UserSettings.pref.get('retrieval_top_k', 3) as number;
    LlmConfig.ENABLE_AGENTIC = UserSettings.agenticEnabled;
    RetrievalConfig.DEFAULT_TOP_K = UserSettings.retrievalTopK;
  }

  static async setAgentic(enabled: boolean): Promise<void> {
    UserSettings.agenticEnabled = enabled;
    LlmConfig.ENABLE_AGENTIC = enabled;
    if (UserSettings.pref !== undefined) {
      await UserSettings.pref.put('agentic_enabled', enabled);
      await UserSettings.pref.flush();
    }
  }

  static async setRetrievalTopK(value: number): Promise<void> {
    const safe: number = Math.max(1, Math.min(5, value));
    UserSettings.retrievalTopK = safe;
    RetrievalConfig.DEFAULT_TOP_K = safe;
    if (UserSettings.pref !== undefined) {
      await UserSettings.pref.put('retrieval_top_k', safe);
      await UserSettings.pref.flush();
    }
  }
}
