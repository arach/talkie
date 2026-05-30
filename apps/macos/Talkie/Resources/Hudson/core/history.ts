namespace Hudson.History {
  export interface Stack<T> {
    past: T[];
    future: T[];
    limit: number;
  }

  export interface Transition<T> {
    history: Stack<T>;
    current: T;
    changed: boolean;
  }

  export function create<T>(limit = 50): Stack<T> {
    return { past: [], future: [], limit };
  }

  export function cloneJSON<T>(value: T): T {
    return JSON.parse(JSON.stringify(value));
  }

  export function snapshot<T>(history: Stack<T>, current: T): Stack<T> {
    const past = history.past.concat([cloneJSON(current)]);
    while (past.length > history.limit) past.shift();
    return { ...history, past, future: [] };
  }

  export function undo<T>(history: Stack<T>, current: T): Transition<T> {
    const past = history.past.slice();
    const prev = past.pop();
    if (prev == null) return { history, current, changed: false };
    const future = history.future.concat([cloneJSON(current)]);
    while (future.length > history.limit) future.shift();
    return { history: { ...history, past, future }, current: prev, changed: true };
  }

  export function redo<T>(history: Stack<T>, current: T): Transition<T> {
    const future = history.future.slice();
    const next = future.pop();
    if (next == null) return { history, current, changed: false };
    const past = history.past.concat([cloneJSON(current)]);
    while (past.length > history.limit) past.shift();
    return { history: { ...history, past, future }, current: next, changed: true };
  }
}
