import { ScheduleDraft } from '../../agent/AgentModels';

export interface ScheduleProvider {
  readonly providerName: string;
  available(): boolean;
  addEvent(draft: ScheduleDraft): Promise<string>;
  listEvents(): Promise<string[]>;
}
