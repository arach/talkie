export class WorkflowCoreError extends Error {
  constructor(
    message: string,
    readonly code:
      | "INVALID_WORKFLOW"
      | "INVALID_STEP"
      | "INVALID_CONTEXT"
      | "UNSUPPORTED_STEP_TYPE"
      | "STEP_EXECUTION_FAILED"
      | "HOST_STEP_FAILED",
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "WorkflowCoreError";
  }
}
