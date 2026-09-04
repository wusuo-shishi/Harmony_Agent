export enum AgentKind {
  General = 'general',
  Learning = 'learning',
  Schedule = 'schedule',
  Document = 'document'
}

export enum StepState {
  Running = 'running',
  Done = 'done',
  Failed = 'failed'
}

export class AgentStep {
  title: string = '';
  detail: string = '';
  state: StepState = StepState.Running;

  static of(title: string): AgentStep {
    const step = new AgentStep();
    step.title = title;
    return step;
  }
}

export class ScheduleDraft {
  title: string = '';
  startTime: number = 0;
  endTime: number = 0;
  reminderMinutes: number = 15;
  location: string = '';
  rawText: string = '';

  static of(title: string, startTime: number, endTime: number): ScheduleDraft {
    const d = new ScheduleDraft();
    d.title = title;
    d.startTime = startTime;
    d.endTime = endTime;
    return d;
  }
}

export class AgentRunResult {
  kind: AgentKind = AgentKind.General;
  agentName: string = '';
  steps: AgentStep[] = [];
  answer: string = '';
  payload: string = '';
}
