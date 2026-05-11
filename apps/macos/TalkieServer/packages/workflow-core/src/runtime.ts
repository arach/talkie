import { WorkflowRuntimeContext } from "./context";
import { WorkflowCoreError } from "./errors";
import { normalizeWorkflowDefinition } from "./normalize";
import type {
  WorkflowHostStepInvocation,
  WorkflowHostStepResult,
  PortableWorkflow,
  PortableWorkflowStep,
  WorkflowExecutionContextInput,
  WorkflowExecutionPlan,
  WorkflowExecutionResult,
  WorkflowStepTrace,
  WorkflowStepType,
} from "./types";

const portableStepTypes = new Set<WorkflowStepType>(["transform", "conditional"]);

function getString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function getObject(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function snapshotContext(context: WorkflowRuntimeContext): WorkflowHostStepInvocation["context"] {
  return {
    transcript: context.transcript,
    title: context.title,
    date: context.date.toISOString(),
    outputs: { ...context.outputs },
    outputOrder: [...context.outputOrder],
  };
}

function stepTypeLabel(stepType: WorkflowStepType): string {
  switch (stepType) {
    case "llm": return "LLM Generation";
    case "shell": return "Shell Command";
    case "webhook": return "Webhook";
    case "email": return "Email";
    case "notification": return "Notification";
    case "iOSPush": return "iOS Push";
    case "appleNotes": return "Apple Notes";
    case "appleReminders": return "Reminder";
    case "appleCalendar": return "Calendar Event";
    case "clipboard": return "Clipboard";
    case "saveFile": return "Save File";
    case "conditional": return "Conditional";
    case "transform": return "Transform";
    case "transcribe": return "Transcribe";
    case "speak": return "Speak";
    case "trigger": return "Trigger";
    case "intentExtract": return "Extract Intents";
    case "executeWorkflows": return "Execute Workflows";
    case "cloudUpload": return "Cloud Upload";
  }
}

function formatStepLabel(step: Pick<PortableWorkflowStep, "id" | "type" | "outputKey">): string {
  const label = stepTypeLabel(step.type);
  return step.outputKey ? `${label} step '${step.outputKey}'` : `${label} step`;
}

function errorMessage(error: unknown): string {
  if (error instanceof WorkflowCoreError) {
    return error.message;
  }
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return "Unknown execution failure.";
}

function formatStepFailure(step: Pick<PortableWorkflowStep, "id" | "type" | "outputKey">, error: unknown): string {
  const message = errorMessage(error);
  const label = formatStepLabel(step);
  return message.startsWith(label) ? message : `${label} failed: ${message}`;
}

function describeStepInput(step: PortableWorkflowStep, context: WorkflowRuntimeContext): string {
  switch (step.type) {
    case "llm":
      return context.resolve(getString(step.config.prompt) ?? "");
    case "shell": {
      const executable = getString(step.config.executable) ?? "";
      const argumentsList = Array.isArray(step.config.arguments)
        ? step.config.arguments.map((value) => context.resolve(String(value)))
        : [];
      const command = [executable, ...argumentsList]
        .filter(Boolean)
        .map((value) => (value.includes(" ") ? `"${value}"` : value))
        .join(" ");
      const stdin = getString(step.config.stdin);
      if (stdin) {
        const resolvedStdin = context.resolve(stdin);
        const preview = resolvedStdin.slice(0, 200);
        return `$ ${command}\n\n[stdin: ${preview}${resolvedStdin.length > 200 ? "..." : ""}]`;
      }
      return `$ ${command}`.trim();
    }
    case "webhook":
      return context.resolve(getString(step.config.url) ?? "");
    case "email":
      return context.resolve(getString(step.config.subject) ?? "");
    case "notification":
    case "iOSPush":
      return context.resolve(getString(step.config.title) ?? "");
    case "appleNotes":
    case "appleReminders":
    case "appleCalendar":
      return context.resolve(getString(step.config.title) ?? "");
    case "clipboard":
    case "saveFile":
    case "speak":
      return context.resolve(getString(step.config.content) ?? getString(step.config.text) ?? "{{OUTPUT}}");
    case "conditional":
      return context.resolve(getString(step.config.condition) ?? "");
    case "transform":
      return context.previousOutput || context.transcript;
    case "transcribe":
      return "Transcribe local memo audio";
    case "trigger":
      return context.transcript;
    case "intentExtract":
      return context.resolve(getString(step.config.inputKey) ?? "{{PREVIOUS_OUTPUT}}");
    case "executeWorkflows":
      return context.resolve(getString(step.config.intentsKey) ?? "{{PREVIOUS_OUTPUT}}");
    case "cloudUpload":
      return context.resolve(getString(step.config.pathTemplate) ?? "");
    default:
      return context.previousOutput || context.transcript;
  }
}

function executeTransformStep(step: PortableWorkflowStep, context: WorkflowRuntimeContext): string {
  const config = step.config;
  const input = context.previousOutput || context.transcript;
  const operation = getString(config.operation) ?? "Extract JSON";
  const parameters = getObject(config.parameters) ?? {};

  switch (operation) {
    case "Extract JSON": {
      const arrayMatch = input.match(/\[[\s\S]*\]/);
      if (arrayMatch) {
        try {
          JSON.parse(arrayMatch[0]);
          return arrayMatch[0];
        } catch {}
      }

      const objectMatch = input.match(/\{[\s\S]*\}/);
      if (objectMatch) {
        try {
          JSON.parse(objectMatch[0]);
          return objectMatch[0];
        } catch {}
      }

      return input;
    }
    case "Extract List": {
      return input
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean)
        .map((line) => `• ${line}`)
        .join("\n");
    }
    case "Format as Markdown":
      return input;
    case "Truncate/Summarize": {
      const maxLengthRaw = parameters.maxLength;
      const maxLength = typeof maxLengthRaw === "number"
        ? maxLengthRaw
        : parseInt(String(maxLengthRaw ?? "500"), 10);
      if (input.length > maxLength) {
        return `${input.slice(0, maxLength)}...`;
      }
      return input;
    }
    case "Regex Extract": {
      const pattern = getString(parameters.pattern);
      if (!pattern) {
        return input;
      }

      const match = input.match(new RegExp(pattern));
      return match?.[0] ?? input;
    }
    case "Apply Template": {
      const template = getString(parameters.template);
      return template ? context.resolve(template) : input;
    }
    default:
      return input;
  }
}

function evaluateCondition(condition: string): boolean {
  const trimmed = condition.trim();

  if (trimmed.includes(" contains ")) {
    const [left, right] = trimmed.split(" contains ");
    const value = right?.trim().replace(/^['"]|['"]$/g, "") ?? "";
    return left?.includes(value) ?? false;
  }

  if (trimmed.includes(" equals ")) {
    const [left, right] = trimmed.split(" equals ");
    const value = right?.trim().replace(/^['"]|['"]$/g, "") ?? "";
    return (left ?? "") === value;
  }

  if (trimmed.includes(" startsWith ")) {
    const [left, right] = trimmed.split(" startsWith ");
    const value = right?.trim().replace(/^['"]|['"]$/g, "") ?? "";
    return (left ?? "").startsWith(value);
  }

  if (trimmed.includes(" endsWith ")) {
    const [left, right] = trimmed.split(" endsWith ");
    const value = right?.trim().replace(/^['"]|['"]$/g, "") ?? "";
    return (left ?? "").endsWith(value);
  }

  if (trimmed.endsWith(" isEmpty")) {
    return trimmed.replace(" isEmpty", "").trim().length === 0;
  }

  if (trimmed.endsWith(" isNotEmpty")) {
    return trimmed.replace(" isNotEmpty", "").trim().length > 0;
  }

  return trimmed.length > 0;
}

function executePortableStep(step: PortableWorkflowStep, context: WorkflowRuntimeContext): string {
  switch (step.type) {
    case "transform":
      return executeTransformStep(step, context);
    case "conditional":
      return evaluateCondition(context.resolve(getString(step.config.condition) ?? "")) ? "true" : "false";
    default:
      throw new WorkflowCoreError(
        `${formatStepLabel(step)} still requires a host runtime.`,
        "UNSUPPORTED_STEP_TYPE",
        { stepType: step.type, stepId: step.id },
      );
  }
}

export function describeWorkflowExecution(workflowInput: unknown): WorkflowExecutionPlan {
  const workflow = normalizeWorkflowDefinition(workflowInput);
  const steps = workflow.steps.map((step) => ({
    id: step.id,
    type: step.type,
    outputKey: step.outputKey,
    runner: portableStepTypes.has(step.type) ? "portable" as const : "host-required" as const,
    reason: portableStepTypes.has(step.type)
      ? undefined
      : "Requires native host or provider-specific execution.",
  }));

  const portable = steps.filter((step) => step.runner === "portable").map((step) => step.type);
  const hostRequired = steps.filter((step) => step.runner === "host-required").map((step) => step.type);

  return {
    portableStepTypes: Array.from(new Set(portable)),
    hostRequiredStepTypes: Array.from(new Set(hostRequired)),
    portableStepCount: portable.length,
    hostRequiredStepCount: hostRequired.length,
    steps,
  };
}

export function executePortableWorkflow(input: {
  workflow: unknown;
  context?: WorkflowExecutionContextInput;
  continueOnUnsupported?: boolean;
}): WorkflowExecutionResult {
  const workflow = normalizeWorkflowDefinition(input.workflow);
  const plan = describeWorkflowExecution(workflow);
  const context = new WorkflowRuntimeContext(input.context);
  const trace: WorkflowStepTrace[] = [];

  for (const step of workflow.steps) {
    const startedAt = performance.now();
    const stepInput = describeStepInput(step, context);

    if (!step.isEnabled) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "portable",
        status: "skipped",
        durationMs: performance.now() - startedAt,
        reason: "Step disabled.",
        input: stepInput,
      });
      continue;
    }

    if (step.condition && !evaluateCondition(context.resolve(step.condition))) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "portable",
        status: "skipped",
        durationMs: performance.now() - startedAt,
        reason: "Condition evaluated false.",
        input: stepInput,
      });
      continue;
    }

    if (!portableStepTypes.has(step.type)) {
      const unsupported = new WorkflowCoreError(
        `${formatStepLabel(step)} still requires a host runtime.`,
        "UNSUPPORTED_STEP_TYPE",
        { stepType: step.type, stepId: step.id },
      );

      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "portable",
        status: "unsupported",
        durationMs: performance.now() - startedAt,
        reason: unsupported.message,
        input: stepInput,
      });

      if (!input.continueOnUnsupported) {
        throw unsupported;
      }
      continue;
    }

    try {
      const output = executePortableStep(step, context);
      context.setOutput(step.outputKey, output);
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "portable",
        status: "completed",
        durationMs: performance.now() - startedAt,
        output,
        input: stepInput,
      });
    } catch (error) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "portable",
        status: "failed",
        durationMs: performance.now() - startedAt,
        reason: error instanceof Error ? error.message : "Unknown execution failure.",
        input: stepInput,
      });

      throw error instanceof WorkflowCoreError
        ? error
        : new WorkflowCoreError(
            formatStepFailure(step, error),
            "STEP_EXECUTION_FAILED",
            { stepId: step.id, stepType: step.type, outputKey: step.outputKey, cause: error },
          );
    }
  }

  return {
    workflow,
    plan,
    outputs: { ...context.outputs },
    outputOrder: [...context.outputOrder],
    trace,
    halted: false,
  };
}

export async function executeWorkflow(input: {
  workflow: unknown;
  context?: WorkflowExecutionContextInput;
  continueOnUnsupported?: boolean;
  runHostStep?: (invocation: WorkflowHostStepInvocation) => Promise<WorkflowHostStepResult>;
}): Promise<WorkflowExecutionResult> {
  const workflow = normalizeWorkflowDefinition(input.workflow);
  const plan = describeWorkflowExecution(workflow);
  const context = new WorkflowRuntimeContext(input.context);
  const trace: WorkflowStepTrace[] = [];
  let halted = false;
  let haltReason: string | undefined;

  for (const step of workflow.steps) {
    const startedAt = performance.now();
    const stepInput = describeStepInput(step, context);

    if (!step.isEnabled) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: portableStepTypes.has(step.type) ? "portable" : "host",
        status: "skipped",
        durationMs: performance.now() - startedAt,
        reason: "Step disabled.",
        input: stepInput,
      });
      continue;
    }

    if (step.condition && !evaluateCondition(context.resolve(step.condition))) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: portableStepTypes.has(step.type) ? "portable" : "host",
        status: "skipped",
        durationMs: performance.now() - startedAt,
        reason: "Condition evaluated false.",
        input: stepInput,
      });
      continue;
    }

    try {
      if (portableStepTypes.has(step.type)) {
        const output = executePortableStep(step, context);
        context.setOutput(step.outputKey, output);
        trace.push({
          stepId: step.id,
          type: step.type,
          outputKey: step.outputKey,
          runner: "portable",
          status: "completed",
          durationMs: performance.now() - startedAt,
          output,
          input: stepInput,
        });
        continue;
      }

      if (!input.runHostStep) {
        const unsupported = new WorkflowCoreError(
          `${formatStepLabel(step)} still requires a host runtime.`,
          "UNSUPPORTED_STEP_TYPE",
          { stepType: step.type, stepId: step.id },
        );

        trace.push({
          stepId: step.id,
          type: step.type,
          outputKey: step.outputKey,
          runner: "host",
          status: "unsupported",
          durationMs: performance.now() - startedAt,
          reason: unsupported.message,
          input: stepInput,
        });

        if (!input.continueOnUnsupported) {
          throw unsupported;
        }
        continue;
      }

      const hostResult = await input.runHostStep({
        step,
        context: snapshotContext(context),
      });

      if (hostResult.status === "halted") {
        halted = true;
        haltReason = hostResult.reason ?? "Host step halted execution.";
        trace.push({
          stepId: step.id,
          type: step.type,
          outputKey: step.outputKey,
          runner: "host",
          status: "halted",
          durationMs: performance.now() - startedAt,
          reason: haltReason,
          input: stepInput,
        });
        break;
      }

      const output = hostResult.output ?? "";
      context.setOutput(step.outputKey, output);
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: "host",
        status: "completed",
        durationMs: performance.now() - startedAt,
        output,
        input: stepInput,
      });
    } catch (error) {
      trace.push({
        stepId: step.id,
        type: step.type,
        outputKey: step.outputKey,
        runner: portableStepTypes.has(step.type) ? "portable" : "host",
        status: "failed",
        durationMs: performance.now() - startedAt,
        reason: error instanceof Error ? error.message : "Unknown execution failure.",
        input: stepInput,
      });

      throw error instanceof WorkflowCoreError
        ? error
        : new WorkflowCoreError(
            formatStepFailure(step, error),
            "STEP_EXECUTION_FAILED",
            { stepId: step.id, stepType: step.type, outputKey: step.outputKey, cause: error },
          );
    }
  }

  return {
    workflow,
    plan,
    outputs: { ...context.outputs },
    outputOrder: [...context.outputOrder],
    trace,
    halted,
    haltReason,
  };
}

export function normalizePortableWorkflow(input: unknown): PortableWorkflow {
  return normalizeWorkflowDefinition(input);
}
