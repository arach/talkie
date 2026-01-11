/**
 * Extensions Module - Diff Engine
 *
 * Simple word-level diff computation.
 * Used for showing before/after changes in LLM revisions.
 */

import type { DiffOperation } from "./types";

/**
 * Compute word-level diff between two strings
 */
export function computeDiff(before: string, after: string): DiffOperation[] {
  const beforeWords = tokenize(before);
  const afterWords = tokenize(after);

  // Use Myers diff algorithm (simplified)
  const ops = myersDiff(beforeWords, afterWords);

  // Merge adjacent operations of the same type
  return mergeOperations(ops);
}

/**
 * Tokenize text into words, preserving whitespace
 */
function tokenize(text: string): string[] {
  const tokens: string[] = [];
  let current = "";
  let inWhitespace = false;

  for (const char of text) {
    const isWs = /\s/.test(char);

    if (isWs !== inWhitespace && current) {
      tokens.push(current);
      current = "";
    }

    current += char;
    inWhitespace = isWs;
  }

  if (current) {
    tokens.push(current);
  }

  return tokens;
}

/**
 * Simplified Myers diff algorithm
 */
function myersDiff(a: string[], b: string[]): DiffOperation[] {
  const ops: DiffOperation[] = [];
  const n = a.length;
  const m = b.length;

  // Build LCS table
  const dp: number[][] = Array(n + 1)
    .fill(null)
    .map(() => Array(m + 1).fill(0));

  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      if (a[i - 1] === b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }

  // Backtrack to build diff
  let i = n;
  let j = m;
  const result: DiffOperation[] = [];

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && a[i - 1] === b[j - 1]) {
      result.unshift({ type: "equal", text: a[i - 1] });
      i--;
      j--;
    } else if (j > 0 && (i === 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      result.unshift({ type: "insert", text: b[j - 1] });
      j--;
    } else if (i > 0) {
      result.unshift({ type: "delete", text: a[i - 1] });
      i--;
    }
  }

  return result;
}

/**
 * Merge adjacent operations of the same type
 */
function mergeOperations(ops: DiffOperation[]): DiffOperation[] {
  if (ops.length === 0) return [];

  const merged: DiffOperation[] = [];
  let current = { ...ops[0] };

  for (let i = 1; i < ops.length; i++) {
    const op = ops[i];
    if (op.type === current.type) {
      current.text += op.text;
    } else {
      merged.push(current);
      current = { ...op };
    }
  }

  merged.push(current);
  return merged;
}
