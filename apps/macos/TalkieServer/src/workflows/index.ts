import { Elysia } from "elysia";
import {
  WorkflowCoreError,
  describeWorkflowExecution,
  executeWorkflow,
  executePortableWorkflow,
  normalizePortableWorkflow,
} from "@talkie/workflow-core";

import { log } from "../log";

type WorkflowRouteBody = {
  memoId?: string;
  workflow?: unknown;
  context?: {
    transcript?: string;
    title?: string;
    date?: string;
    outputs?: Record<string, string>;
    outputOrder?: string[];
  };
  options?: {
    continueOnUnsupported?: boolean;
  };
};

const swiftWorkflowHostURL = "http://127.0.0.1:8766/workflows/host/execute-step";

type WorkflowStepSummary = {
  id: string;
  type: string;
  outputKey?: string;
};

function stepTypeLabel(stepType: string): string {
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
    default: return stepType;
  }
}

function formatStepLabel(step: WorkflowStepSummary): string {
  const label = stepTypeLabel(step.type);
  return step.outputKey ? `${label} step '${step.outputKey}'` : `${label} step`;
}

function connectionRefused(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }

  const details = error as {
    cause?: {
      code?: string;
      errno?: number;
    };
  };

  return details.cause?.code === "ECONNREFUSED" || details.cause?.errno === 61;
}

function hostFetchErrorDetails(step: WorkflowStepSummary, error: unknown) {
  return {
    stepId: step.id,
    stepType: step.type,
    cause: error,
  };
}

function formatHostStepFailure(step: WorkflowStepSummary, message: string): string {
  const label = formatStepLabel(step);
  return message.startsWith(label) ? message : `${label} failed: ${message}`;
}

function badRequest(message: string, details?: unknown) {
  return {
    ok: false,
    error: message,
    details,
  };
}

function parseBody(body: unknown): WorkflowRouteBody {
  if (!body || typeof body !== "object") {
    throw new WorkflowCoreError("Request body must be an object.", "INVALID_WORKFLOW");
  }
  return body as WorkflowRouteBody;
}

export const workflows = new Elysia({ name: "workflows" })
  .post("/workflows/portable/plan", async ({ request, set }) => {
    try {
      const body = parseBody(await request.json());
      if (body.workflow === undefined) {
        set.status = 400;
        return badRequest("Missing workflow definition.");
      }

      const workflow = normalizePortableWorkflow(body.workflow);
      const plan = describeWorkflowExecution(workflow);

      return {
        ok: true,
        workflow,
        plan,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to plan workflow.";
      log.warn(`Workflow plan failed: ${message}`);
      set.status = error instanceof WorkflowCoreError ? 400 : 500;
      return badRequest(message, error instanceof WorkflowCoreError ? error.details : undefined);
    }
  })
  .post("/workflows/portable/run", async ({ request, set }) => {
    try {
      const body = parseBody(await request.json());
      if (body.workflow === undefined) {
        set.status = 400;
        return badRequest("Missing workflow definition.");
      }

      return {
        ok: true,
        result: executePortableWorkflow({
          workflow: body.workflow,
          context: body.context,
          continueOnUnsupported: body.options?.continueOnUnsupported ?? false,
        }),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Portable workflow execution failed.";
      log.warn(`Workflow run failed: ${message}`);
      set.status = error instanceof WorkflowCoreError ? 400 : 500;
      return badRequest(message, error instanceof WorkflowCoreError ? error.details : undefined);
    }
  })
  .post("/workflows/run", async ({ request, set }) => {
    try {
      const body = parseBody(await request.json());
      if (body.workflow === undefined) {
        set.status = 400;
        return badRequest("Missing workflow definition.");
      }
      if (!body.memoId) {
        set.status = 400;
        return badRequest("Missing memoId.");
      }

      const result = await executeWorkflow({
        workflow: body.workflow,
        context: body.context,
        continueOnUnsupported: body.options?.continueOnUnsupported ?? false,
        runHostStep: async ({ step, context }) => {
          try {
            const response = await fetch(swiftWorkflowHostURL, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                memoId: body.memoId,
                stepId: step.id,
                stepType: step.type,
                outputKey: step.outputKey,
                configJSON: JSON.stringify(step.config),
                context,
              }),
            });

            const responseText = await response.text();
            const payload = responseText.length > 0
              ? JSON.parse(responseText) as {
                  ok?: boolean;
                  error?: string;
                  result?: {
                    status?: "completed" | "halted";
                    output?: string;
                    reason?: string;
                  };
                }
              : {};

            if (!response.ok || payload.ok === false || !payload.result) {
              const message = formatHostStepFailure(
                step,
                payload.error ?? `Host step request failed with status ${response.status}.`,
              );

              throw new WorkflowCoreError(
                message,
                "HOST_STEP_FAILED",
                {
                  status: response.status,
                  stepId: step.id,
                  stepType: step.type,
                  outputKey: step.outputKey,
                  hostError: payload.error,
                },
              );
            }

            return payload.result;
          } catch (error) {
            if (error instanceof WorkflowCoreError) {
              throw error;
            }

            const message = connectionRefused(error)
              ? `Could not reach Talkie's local workflow host while running ${formatStepLabel(step)}. Try rerunning the workflow or restarting Talkie.`
              : formatHostStepFailure(
                  step,
                  error instanceof Error ? error.message : "Unknown host execution failure.",
                );

            throw new WorkflowCoreError(
              message,
              "HOST_STEP_FAILED",
              hostFetchErrorDetails(step, error),
            );
          }
        },
      });

      return {
        ok: true,
        result,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Workflow execution failed.";
      log.warn(`Workflow execution failed: ${message}`);
      set.status = error instanceof WorkflowCoreError ? 400 : 500;
      return badRequest(message, error instanceof WorkflowCoreError ? error.details : undefined);
    }
  });
