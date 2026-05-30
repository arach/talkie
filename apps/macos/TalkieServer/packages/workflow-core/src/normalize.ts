import { WorkflowCoreError } from "./errors";
import { slugifyWorkflowName } from "./slug";
import type {
  PortableWorkflow,
  PortableWorkflowStep,
  WorkflowStepType,
} from "./types";
import { workflowStepTypes } from "./types";

type UnknownRecord = Record<string, unknown>;

const metadataKeys = new Set([
  "id",
  "type",
  "config",
  "outputKey",
  "isEnabled",
  "condition",
]);

const configKeysByType: Record<WorkflowStepType, string> = {
  llm: "llm",
  shell: "shell",
  webhook: "webhook",
  email: "email",
  notification: "notification",
  iOSPush: "iOSPush",
  appleNotes: "appleNotes",
  appleReminders: "appleReminders",
  appleCalendar: "appleCalendar",
  clipboard: "clipboard",
  saveFile: "saveFile",
  conditional: "conditional",
  transform: "transform",
  transcribe: "transcribe",
  speak: "speak",
  trigger: "trigger",
  intentExtract: "intentExtract",
  executeWorkflows: "executeWorkflows",
  cloudUpload: "cloudUpload",
};

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unwrapSwiftEnumPayload(value: UnknownRecord): UnknownRecord {
  const keys = Object.keys(value);
  if (keys.length === 1 && keys[0] === "_0") {
    const payload = value._0;
    if (isRecord(payload)) {
      return payload;
    }
  }

  return value;
}

function normalizeConfig(step: UnknownRecord, type: WorkflowStepType): Record<string, unknown> {
  const nested = step.config;
  if (isRecord(nested)) {
    const preferredKey = configKeysByType[type];
    const preferredConfig = nested[preferredKey];
    if (isRecord(preferredConfig)) {
      return unwrapSwiftEnumPayload(preferredConfig);
    }

    const nestedKeys = Object.keys(nested);
    if (nestedKeys.length === 1) {
      const onlyValue = nested[nestedKeys[0]];
      if (isRecord(onlyValue)) {
        return unwrapSwiftEnumPayload(onlyValue);
      }
    }

    return unwrapSwiftEnumPayload(nested);
  }

  const flatConfig: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(step)) {
    if (!metadataKeys.has(key) && value !== undefined) {
      flatConfig[key] = value;
    }
  }

  if (type === "conditional" && typeof step.condition === "string") {
    flatConfig.condition = step.condition;
  }

  return flatConfig;
}

function normalizeStep(step: unknown, index: number): PortableWorkflowStep {
  if (!isRecord(step)) {
    throw new WorkflowCoreError(
      `Step ${index + 1} must be an object.`,
      "INVALID_STEP",
      { index, step },
    );
  }

  const type = step.type;
  if (typeof type !== "string" || !workflowStepTypes.includes(type as WorkflowStepType)) {
    throw new WorkflowCoreError(
      `Step ${index + 1} has unsupported type '${String(type)}'.`,
      "INVALID_STEP",
      { index, type },
    );
  }

  const condition = typeof step.condition === "string"
    ? step.condition
    : isRecord(step.condition) && typeof step.condition.expression === "string"
      ? step.condition.expression
      : undefined;

  return {
    id: typeof step.id === "string" && step.id.length > 0 ? step.id : `step-${index + 1}`,
    type: type as WorkflowStepType,
    outputKey: typeof step.outputKey === "string" && step.outputKey.length > 0
      ? step.outputKey
      : `step_${index}`,
    isEnabled: typeof step.isEnabled === "boolean" ? step.isEnabled : true,
    condition: type === "conditional" && !("config" in step) ? undefined : condition,
    config: normalizeConfig(step, type as WorkflowStepType),
  };
}

export function normalizeWorkflowDefinition(input: unknown, slugHint?: string): PortableWorkflow {
  if (!isRecord(input)) {
    throw new WorkflowCoreError("Workflow definition must be an object.", "INVALID_WORKFLOW");
  }

  const steps = input.steps;
  if (!Array.isArray(steps)) {
    throw new WorkflowCoreError("Workflow definition must include a steps array.", "INVALID_WORKFLOW");
  }

  const name = typeof input.name === "string" && input.name.length > 0 ? input.name : "Untitled Workflow";
  const slug = typeof input.slug === "string" && input.slug.length > 0
    ? input.slug
    : slugifyWorkflowName(slugHint ?? name);

  return {
    slug,
    name,
    description: typeof input.description === "string" ? input.description : "",
    icon: typeof input.icon === "string" && input.icon.length > 0 ? input.icon : "wand.and.stars",
    color: typeof input.color === "string" && input.color.length > 0 ? input.color : "blue",
    maintainer: typeof input.maintainer === "string" ? input.maintainer : null,
    isEnabled: typeof input.isEnabled === "boolean" ? input.isEnabled : true,
    isPinned: typeof input.isPinned === "boolean" ? input.isPinned : false,
    autoRun: typeof input.autoRun === "boolean" ? input.autoRun : false,
    steps: steps.map(normalizeStep),
  };
}
