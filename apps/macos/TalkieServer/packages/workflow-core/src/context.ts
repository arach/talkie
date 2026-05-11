import type { WorkflowExecutionContextInput } from "./types";

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

function formatDate(date: Date): string {
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join("-");
}

function formatDateTime(date: Date): string {
  return `${formatDate(date)}_${pad(date.getHours())}-${pad(date.getMinutes())}`;
}

function sanitizeForFilename(input: string): string {
  return input
    .replaceAll(":", "-")
    .replaceAll("/", "-")
    .replaceAll("\\", "-")
    .replaceAll("*", "")
    .replaceAll("?", "")
    .replaceAll("\"", "'")
    .replaceAll("<", "")
    .replaceAll(">", "")
    .replaceAll("|", "-")
    .replaceAll("\n", " ")
    .replaceAll("\r", "");
}

export class WorkflowRuntimeContext {
  transcript: string;
  title: string;
  date: Date;
  outputs: Record<string, string>;
  outputOrder: string[];

  constructor(input: WorkflowExecutionContextInput = {}) {
    this.transcript = input.transcript ?? "";
    this.title = input.title ?? "Untitled";
    this.date = input.date instanceof Date
      ? input.date
      : typeof input.date === "number"
        ? new Date(input.date > 1_000_000_000_000 ? input.date : input.date * 1000)
      : input.date
        ? new Date(input.date)
        : new Date();
    this.outputs = { ...(input.outputs ?? {}) };
    this.outputOrder = [...(input.outputOrder ?? Object.keys(this.outputs))];
  }

  get previousOutput(): string {
    const lastKey = this.outputOrder[this.outputOrder.length - 1];
    return lastKey ? this.outputs[lastKey] ?? "" : "";
  }

  resolve(template: string): string {
    let result = template;

    result = result.replaceAll("{{TRANSCRIPT}}", this.transcript);
    result = result.replaceAll("{{TITLE}}", sanitizeForFilename(this.title));
    result = result.replaceAll("{{DATE}}", formatDate(this.date));
    result = result.replaceAll("{{DATETIME}}", formatDateTime(this.date));
    result = result.replaceAll("{{PREVIOUS_OUTPUT}}", this.previousOutput);
    result = result.replaceAll("{{OUTPUT}}", this.previousOutput);

    for (const [key, value] of Object.entries(this.outputs)) {
      result = result.replaceAll(`{{${key}}}`, value);
    }

    return result;
  }

  setOutput(key: string, value: string): void {
    if (!this.outputOrder.includes(key)) {
      this.outputOrder.push(key);
    }
    this.outputs[key] = value;
  }
}
