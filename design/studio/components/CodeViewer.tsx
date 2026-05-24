"use client";

import CodeMirror from "@uiw/react-codemirror";
import { javascript } from "@codemirror/lang-javascript";
import { markdown } from "@codemirror/lang-markdown";
import { json } from "@codemirror/lang-json";
import { css as cssLang } from "@codemirror/lang-css";
import { html } from "@codemirror/lang-html";
import { swift } from "@codemirror/legacy-modes/mode/swift";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { StreamLanguage } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";
import { githubLight, githubDark } from "@uiw/codemirror-theme-github";
import { useEffect, useState } from "react";

/**
 * Read-only code viewer for file references inside engineering docs.
 *
 * CodeMirror 6 in display mode — line numbers, language-aware
 * highlighting, no editing affordances. Theme follows the OS color
 * scheme so it sits cleanly in Studio today (light) and in whatever
 * dark-mode pass lands next.
 *
 * Language pack covers the file extensions actually referenced in the
 * TLK series (Swift, TS/TSX/JS, Markdown, JSON, CSS, HTML, shell,
 * YAML, TOML). Unknown extensions render as plain text — no error.
 */
interface CodeViewerProps {
  content: string;
  filename: string;
}

export function CodeViewer({ content, filename }: CodeViewerProps) {
  const [theme, setTheme] = useState<"light" | "dark">("light");

  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => setTheme(mq.matches ? "dark" : "light");
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  const lang = languageForFilename(filename);
  const extensions: Extension[] = [
    EditorView.editable.of(false),
    EditorView.contentAttributes.of({ tabindex: "0" }),
    EditorView.theme({
      ".cm-scroller": {
        fontFamily:
          '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
        fontSize: "12.5px",
        lineHeight: "1.55",
      },
    }),
  ];
  if (lang) extensions.push(lang);

  return (
    <CodeMirror
      value={content}
      readOnly
      theme={theme === "dark" ? githubDark : githubLight}
      extensions={extensions}
      basicSetup={{
        lineNumbers: true,
        highlightActiveLine: false,
        highlightActiveLineGutter: false,
        foldGutter: true,
        dropCursor: false,
        allowMultipleSelections: false,
        autocompletion: false,
        bracketMatching: true,
        closeBrackets: false,
        crosshairCursor: false,
        indentOnInput: false,
      }}
    />
  );
}

function languageForFilename(filename: string): Extension | null {
  const ext = filename.split(".").pop()?.toLowerCase() ?? "";
  switch (ext) {
    case "swift":
      return StreamLanguage.define(swift);
    case "ts":
      return javascript({ typescript: true });
    case "tsx":
      return javascript({ typescript: true, jsx: true });
    case "js":
      return javascript();
    case "jsx":
      return javascript({ jsx: true });
    case "md":
    case "mdx":
      return markdown();
    case "json":
      return json();
    case "css":
    case "scss":
      return cssLang();
    case "html":
    case "htm":
      return html();
    case "sh":
    case "bash":
    case "zsh":
      return StreamLanguage.define(shell);
    case "yaml":
    case "yml":
      return StreamLanguage.define(yaml);
    case "toml":
      return StreamLanguage.define(toml);
    default:
      return null;
  }
}
