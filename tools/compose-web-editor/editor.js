import { Compartment, EditorSelection, EditorState, RangeSetBuilder, StateEffect, StateField } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap, indentWithTab, redo, redoDepth, undo, undoDepth } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { bracketMatching, defaultHighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { Decoration, EditorView, ViewPlugin, WidgetType, drawSelection, dropCursor, highlightActiveLine, highlightSpecialChars, keymap, placeholder } from "@codemirror/view";

const handlerName = "talkieEditor";
const placeholderCompartment = new Compartment();
const appearanceCompartment = new Compartment();
const editableCompartment = new Compartment();

const setReviewRangesEffect = StateEffect.define();
const clearReviewRangesEffect = StateEffect.define();

function post(message) {
  try {
    window.webkit?.messageHandlers?.[handlerName]?.postMessage(message);
  } catch (error) {
    console.debug("Talkie editor bridge unavailable", error);
  }
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function cssString(value, fallback) {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function cssNumber(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function makeAppearance(config = {}) {
  const text = cssString(config.textColor, "#232423");
  const muted = cssString(config.mutedTextColor, "rgba(35,36,35,0.52)");
  const accent = cssString(config.accentColor, "#9A6A22");
  const selection = cssString(config.selectionColor, "rgba(154,106,34,0.22)");
  const deletion = cssString(config.deletionColor, "rgba(196,58,28,0.18)");
  const deletionBorder = cssString(config.deletionBorderColor, "rgba(196,58,28,0.40)");
  const insertion = cssString(config.insertionColor, "rgba(57,128,74,0.18)");
  const insertionBorder = cssString(config.insertionBorderColor, "rgba(57,128,74,0.40)");
  const widgetBackground = cssString(config.widgetBackgroundColor, "rgba(248,248,247,0.96)");
  const fontSize = cssNumber(config.fontSize, 14);
  const lineHeight = cssNumber(config.lineHeight, 1.58);

  return EditorView.theme({
    "&": {
      height: "100%",
      color: text,
      background: "transparent",
      fontSize: `${fontSize}px`,
    },
    "&.cm-focused": { outline: "none" },
    ".cm-scroller": {
      height: "100%",
      overflow: "auto",
      fontFamily: 'ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, sans-serif',
      lineHeight: String(lineHeight),
    },
    ".cm-content": {
      minHeight: "100%",
      padding: "0",
      caretColor: accent,
    },
    ".cm-line": {
      padding: "0",
    },
    ".cm-placeholder": {
      color: muted,
    },
    ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
      backgroundColor: selection,
    },
    ".cm-cursor": {
      borderLeftColor: accent,
      borderLeftWidth: "1.5px",
    },
    ".cm-activeLine": {
      backgroundColor: "transparent",
    },
    ".cm-specialChar": {
      color: muted,
      border: "none",
    },
    ".tok-heading": {
      color: text,
      fontFamily: 'Newsreader, "Iowan Old Style", Georgia, serif',
      fontWeight: "500",
    },
    ".tok-emphasis": { fontStyle: "italic" },
    ".tok-strong": { fontWeight: "650" },
    ".tok-link": { color: accent, textDecoration: "underline", textUnderlineOffset: "2px" },
    ".tok-monospace": {
      fontFamily: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
      fontSize: "0.92em",
    },
    ".talkie-review": {
      borderRadius: "3px",
      padding: "0 1px",
      boxDecorationBreak: "clone",
      WebkitBoxDecorationBreak: "clone",
    },
    ".talkie-review-insertion": {
      backgroundColor: insertion,
      boxShadow: `inset 0 -1px 0 ${insertionBorder}`,
    },
    ".talkie-review-deletion": {
      backgroundColor: deletion,
      boxShadow: `inset 0 -1px 0 ${deletionBorder}`,
      textDecoration: "line-through",
      textDecorationColor: deletionBorder,
    },
    ".talkie-review-replacement": {
      backgroundColor: selection,
      boxShadow: `inset 0 -1px 0 ${accent}`,
    },
    ".talkie-review-widget": {
      display: "inline-flex",
      alignItems: "center",
      gap: "2px",
      marginLeft: "4px",
      padding: "1px 3px",
      verticalAlign: "1px",
      border: `0.5px solid ${accent}`,
      borderRadius: "3px",
      background: widgetBackground,
      color: accent,
      fontFamily: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
      fontSize: "9px",
      fontWeight: "600",
      letterSpacing: "0.08em",
      userSelect: "none",
    },
    ".talkie-review-widget button": {
      border: "0",
      background: "transparent",
      color: "inherit",
      font: "inherit",
      padding: "0 2px",
      cursor: "pointer",
    },
    ".talkie-review-widget button:hover": {
      background: selection,
    },
  });
}

class ReviewWidget extends WidgetType {
  constructor(id, kind) {
    super();
    this.id = id;
    this.kind = kind;
  }

  eq(other) {
    return other.id === this.id && other.kind === this.kind;
  }

  toDOM() {
    const wrap = document.createElement("span");
    wrap.className = "talkie-review-widget";
    wrap.contentEditable = "false";
    wrap.dataset.reviewId = this.id;
    wrap.dataset.reviewKind = this.kind;
    wrap.setAttribute("aria-label", "Review change");

    const accept = document.createElement("button");
    accept.type = "button";
    accept.textContent = "✓";
    accept.title = "Accept change";
    accept.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      post({ type: "reviewAction", id: this.id, action: "accept" });
    });

    const reject = document.createElement("button");
    reject.type = "button";
    reject.textContent = "×";
    reject.title = "Reject change";
    reject.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      post({ type: "reviewAction", id: this.id, action: "reject" });
    });

    wrap.append(accept, reject);
    return wrap;
  }

  ignoreEvent() {
    return false;
  }
}

function buildReviewDecorations(ranges, docLength) {
  const builder = new RangeSetBuilder();
  const normalized = Array.isArray(ranges)
    ? ranges
        .map((range, index) => {
          const from = clamp(Number(range.from) || 0, 0, docLength);
          const to = clamp(Number(range.to) || from, from, docLength);
          return {
            id: String(range.id ?? index),
            kind: String(range.kind ?? "replacement"),
            from,
            to,
          };
        })
        .sort((a, b) => a.from - b.from || a.to - b.to)
    : [];

  for (const range of normalized) {
    const kindClass = range.kind === "deletion"
      ? "talkie-review-deletion"
      : range.kind === "insertion"
        ? "talkie-review-insertion"
        : "talkie-review-replacement";

    if (range.to > range.from) {
      builder.add(
        range.from,
        range.to,
        Decoration.mark({
          class: `talkie-review ${kindClass}`,
          attributes: { "data-review-id": range.id },
        })
      );
    }

    builder.add(
      range.to,
      range.to,
      Decoration.widget({
        widget: new ReviewWidget(range.id, range.kind),
        side: 1,
      })
    );
  }

  return builder.finish();
}

const reviewField = StateField.define({
  create() {
    return Decoration.none;
  },
  update(value, transaction) {
    let next = value.map(transaction.changes);
    for (const effect of transaction.effects) {
      if (effect.is(setReviewRangesEffect)) {
        next = buildReviewDecorations(effect.value, transaction.state.doc.length);
      } else if (effect.is(clearReviewRangesEffect)) {
        next = Decoration.none;
      }
    }
    return next;
  },
  provide(field) {
    return EditorView.decorations.from(field);
  },
});

const nativeFocusBridge = EditorView.domEventHandlers({
  focus() {
    post({ type: "focus" });
  },
  blur() {
    post({ type: "blur" });
  },
  mousedown() {
    post({ type: "focus" });
  },
  touchstart() {
    post({ type: "focus" });
  },
});

const updateBridgePlugin = ViewPlugin.fromClass(class {
  update(update) {
    if (update.docChanged) {
      post({
        type: "change",
        text: update.state.doc.toString(),
        canUndo: undoDepth(update.state) > 0,
        canRedo: redoDepth(update.state) > 0,
      });
    }

    if (update.selectionSet || update.docChanged) {
      const selection = update.state.selection.main;
      post({
        type: "selection",
        anchor: selection.anchor,
        head: selection.head,
        from: selection.from,
        to: selection.to,
        empty: selection.empty,
      });
    }
  }
});

function makeState(doc = "") {
  return EditorState.create({
    doc,
    extensions: [
      history(),
      highlightSpecialChars(),
      drawSelection(),
      dropCursor(),
      bracketMatching(),
      highlightActiveLine(),
      markdown(),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      EditorView.lineWrapping,
      nativeFocusBridge,
      keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap]),
      placeholderCompartment.of(placeholder("")),
      appearanceCompartment.of(makeAppearance()),
      editableCompartment.of(EditorView.editable.of(true)),
      reviewField,
      updateBridgePlugin,
    ],
  });
}

let view;

function ensureView() {
  if (view) return view;
  const parent = document.getElementById("editor");
  view = new EditorView({
    state: makeState(""),
    parent,
  });
  document.body.classList.add("talkie-editor-ready");
  document.body.dataset.talkieEditorEngine = "codemirror6";
  return view;
}

function configure(config = {}) {
  const editor = ensureView();
  const effects = [];
  if (Object.prototype.hasOwnProperty.call(config, "placeholder")) {
    effects.push(placeholderCompartment.reconfigure(placeholder(String(config.placeholder ?? ""))));
  }
  effects.push(appearanceCompartment.reconfigure(makeAppearance(config)));
  if (Object.prototype.hasOwnProperty.call(config, "editable")) {
    effects.push(editableCompartment.reconfigure(EditorView.editable.of(Boolean(config.editable))));
  }
  editor.dispatch({ effects });
}

function getText() {
  return ensureView().state.doc.toString();
}

function setText(text) {
  const editor = ensureView();
  const nextText = String(text ?? "");
  const current = editor.state.doc.toString();
  if (current === nextText) return;

  const cursor = editor.state.selection.main.head;
  editor.dispatch({
    changes: { from: 0, to: editor.state.doc.length, insert: nextText },
    selection: EditorSelection.cursor(clamp(cursor, 0, nextText.length)),
  });
}

function getSelection() {
  const selection = ensureView().state.selection.main;
  return {
    anchor: selection.anchor,
    head: selection.head,
    from: selection.from,
    to: selection.to,
    empty: selection.empty,
  };
}

function setSelection(selection = {}) {
  const editor = ensureView();
  const docLength = editor.state.doc.length;
  const anchor = clamp(Number(selection.anchor ?? selection.from ?? 0), 0, docLength);
  const head = clamp(Number(selection.head ?? selection.to ?? anchor), 0, docLength);
  editor.dispatch({ selection: EditorSelection.single(anchor, head), scrollIntoView: true });
  editor.focus();
}

function insertTextAtCursor(text) {
  const editor = ensureView();
  editor.dispatch(editor.state.replaceSelection(String(text ?? "")));
  editor.focus();
}

function replaceRange(from, to, text) {
  const editor = ensureView();
  const docLength = editor.state.doc.length;
  const start = clamp(Number(from) || 0, 0, docLength);
  const end = clamp(Number(to) || start, start, docLength);
  const insert = String(text ?? "");
  editor.dispatch({
    changes: { from: start, to: end, insert },
    selection: EditorSelection.cursor(start + insert.length),
    scrollIntoView: true,
  });
  editor.focus();
}

function focusEditor() {
  ensureView().focus();
}

function blurEditor() {
  ensureView().contentDOM.blur();
}

function setReviewRanges(ranges) {
  ensureView().dispatch({ effects: setReviewRangesEffect.of(ranges) });
}

function clearReviewRanges() {
  ensureView().dispatch({ effects: clearReviewRangesEffect.of(null) });
}

function performUndo() {
  return undo(ensureView());
}

function performRedo() {
  return redo(ensureView());
}

window.TalkieEditor = {
  configure,
  getText,
  setText,
  getSelection,
  setSelection,
  insertTextAtCursor,
  replaceRange,
  focus: focusEditor,
  blur: blurEditor,
  undo: performUndo,
  redo: performRedo,
  setReviewRanges,
  clearReviewRanges,
};

window.addEventListener("DOMContentLoaded", () => {
  ensureView();
  post({ type: "ready" });
});
