export const workflowStepTypes = [
  "llm",
  "shell",
  "webhook",
  "email",
  "notification",
  "iOSPush",
  "appleNotes",
  "appleReminders",
  "appleCalendar",
  "clipboard",
  "saveFile",
  "conditional",
  "transform",
  "transcribe",
  "speak",
  "trigger",
  "intentExtract",
  "executeWorkflows",
  "cloudUpload",
] as const;

export type WorkflowStepType = (typeof workflowStepTypes)[number];

export interface WorkflowExecutionContextInput {
  transcript?: string;
  title?: string;
  date?: Date | string | number;
  outputs?: Record<string, string>;
  outputOrder?: string[];
}

export interface PortableWorkflowStep {
  id: string;
  type: WorkflowStepType;
  outputKey: string;
  isEnabled: boolean;
  condition?: string;
  config: Record<string, unknown>;
}

export interface PortableWorkflow {
  slug: string;
  name: string;
  description: string;
  icon: string;
  color: string;
  maintainer?: string | null;
  isEnabled: boolean;
  isPinned: boolean;
  autoRun: boolean;
  steps: PortableWorkflowStep[];
}

export interface WorkflowPlanStep {
  id: string;
  type: WorkflowStepType;
  outputKey: string;
  runner: "portable" | "host-required";
  reason?: string;
}

export interface WorkflowExecutionPlan {
  portableStepTypes: WorkflowStepType[];
  hostRequiredStepTypes: WorkflowStepType[];
  portableStepCount: number;
  hostRequiredStepCount: number;
  steps: WorkflowPlanStep[];
}

export interface WorkflowStepTrace {
  stepId: string;
  type: WorkflowStepType;
  outputKey: string;
  runner: "portable" | "host";
  status: "completed" | "skipped" | "unsupported" | "failed" | "halted";
  durationMs: number;
  reason?: string;
  output?: string;
  input?: string;
}

export interface WorkflowHostStepInvocation {
  step: PortableWorkflowStep;
  context: {
    transcript: string;
    title: string;
    date: string;
    outputs: Record<string, string>;
    outputOrder: string[];
  };
}

export interface WorkflowHostStepResult {
  status?: "completed" | "halted";
  output?: string;
  reason?: string;
}

export interface WorkflowExecutionResult {
  workflow: PortableWorkflow;
  plan: WorkflowExecutionPlan;
  outputs: Record<string, string>;
  outputOrder: string[];
  trace: WorkflowStepTrace[];
  halted: boolean;
  haltReason?: string;
}
