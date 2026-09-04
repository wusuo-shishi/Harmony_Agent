import { AgentStep } from './AgentModels';

export type StepListener = (steps: AgentStep[]) => void;
