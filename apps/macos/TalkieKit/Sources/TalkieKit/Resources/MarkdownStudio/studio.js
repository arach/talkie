/* ══════════════════════════════════════════════════════════════════════
   Talkie Markdown — studio chrome
   Wraps the shipped CodeMirror 6 core (window.TalkieEditor, from
   ../ComposeWebEditor/editor.js) with the "Talkie Markdown" design:
   toolbar, Split/Preview/Source, format tools, live preview, revisions,
   and a simulated dictation HUD.

   Text flow:
     • in-app  — editor.js posts 'change' to Swift; Swift forwards the text
                 back via window.TalkieStudio.onText(text) (+ autosave).
     • browser — a webkit stub routes editor.js posts straight here so the
                 page is runnable standalone for iteration.
   ══════════════════════════════════════════════════════════════════════ */
(function () {
  "use strict";

  // ── environment ───────────────────────────────────────────────────────
  var IN_APP = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.talkieEditor);

  function sendNative(msg) {
    try { window.webkit.messageHandlers.talkieEditor.postMessage(msg); } catch (e) { /* noop */ }
  }

  // ── tiny helpers ───────────────────────────────────────────────────────
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function ed() { return window.TalkieEditor; }
  function stats(t) {
    var words = (t.trim().match(/\S+/g) || []).length;
    var mins = Math.max(1, Math.round(words / 200));
    return { words: words, mins: mins };
  }
  function fmtTime(sec) {
    var m = Math.floor(sec / 60), s = sec % 60;
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
  }

  // ── icons ──────────────────────────────────────────────────────────────
  var MIC = '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="3" width="6" height="10" rx="3"></rect><path d="M6 11a6 6 0 0 0 12 0M12 17v3"></path></svg>';
  var BOLT = '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4 14l5-10 2 7h9"></path></svg>';
  var PEN = '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20s2-1 4-3M9 15l7-7 3 3-7 7z"></path></svg>';
  var RST = '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12a8 8 0 1 1 2.3 5.6"></path><path d="M4 12H2M4 12V9"></path></svg>';
  var SPK = '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v4M12 17v4M3 12h4M17 12h4"></path></svg>';
  var CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 6"></path></svg>';

  // ── waveform (deterministic, seeded — real amplitudes slot in later) ────
  function hashSeed(str) { var h = 53; for (var i = 0; i < str.length; i++) { h = (Math.imul(h, 33) + str.charCodeAt(i)) | 0; } return h >>> 0; }
  function waveBars(W, H, n, seed) {
    var s = seed >>> 0;
    var rnd = function () { s = (Math.imul(s, 1103515245) + 12345) & 0x7fffffff; return s / 0x7fffffff; };
    var mid = H / 2, d = "";
    for (var i = 0; i < n; i++) {
      var env = 0.3 + 0.7 * Math.sin((i / (n - 1)) * Math.PI);
      var h = Math.max(2, (0.24 + 0.76 * rnd()) * env * H * 0.86);
      var x = +((i + 0.5) * (W / n)).toFixed(1);
      d += "M" + x + " " + (mid - h / 2).toFixed(1) + "L" + x + " " + (mid + h / 2).toFixed(1);
    }
    return d;
  }

  // ── markdown → HTML (marked + custom ::: dictation container) ───────────
  function renderDictation(info, body) {
    var attrs = {};
    String(info).replace(/(\w+)="([^"]*)"/g, function (_, k, v) { attrs[k] = v; return _; });
    var words = attrs.words || String((body.trim().match(/\S+/g) || []).length);
    var dur = attrs.duration || "0:00";
    var wave = waveBars(220, 24, 46, hashSeed(attrs.title || body));
    var q = body.trim().replace(/^["“]/, "").replace(/["”]$/, "");
    return '<div class="dictation"><div class="dc-top">' +
      '<span class="dc-mic">' + MIC + '</span>' +
      '<span class="dc-label">Dictated block</span><span class="spacer"></span>' +
      '<span class="dc-badge">' + esc(dur) + " · " + esc(words) + ' w</span></div>' +
      '<div class="dc-body"><svg class="dc-wave" viewBox="0 0 220 24" preserveAspectRatio="none">' +
      '<path d="' + wave + '" stroke="var(--acc)" stroke-width="1.7" stroke-linecap="round"></path></svg>' +
      '<p class="dc-quote">“' + esc(q) + '”</p></div></div>';
  }

  function renderMemo(info, body) {
    var attrs = {};
    String(info).replace(/(\w+)="([^"]*)"/g, function (_, k, v) { attrs[k] = v; return _; });
    var inner;
    try { inner = window.marked.parseInline(body.trim(), { gfm: true }); }
    catch (e) { inner = esc(body.trim()); }
    return '<div class="memo"><div class="mc-top"><span class="mc-icon">' + PEN + '</span>' +
      '<span class="mc-label">Memo</span></div>' +
      '<div class="mc-body">' + inner + '</div></div>';
  }

  function renderMarkdown(md) {
    var blocks = [];
    var stripped = String(md).replace(
      /^:::[ \t]*(dictation|memo)[ \t]*([^\n]*)\n([\s\S]*?)\n:::[ \t]*$/gm,
      function (_, type, info, body) {
        var i = blocks.length;
        blocks.push(type === "memo" ? renderMemo(info, body) : renderDictation(info, body));
        return "\n\n@@DICT" + i + "@@\n\n";
      }
    );

    var html = "";
    try { html = window.marked.parse(stripped, { gfm: true, breaks: false }); }
    catch (e) { html = "<p>" + esc(stripped) + "</p>"; }

    var tmp = document.createElement("div");
    tmp.innerHTML = html;

    // dictation placeholders (marked wraps the token in a <p>)
    tmp.querySelectorAll("p").forEach(function (p) {
      var m = p.textContent.trim().match(/^@@DICT(\d+)@@$/);
      if (m) { var holder = document.createElement("div"); holder.innerHTML = blocks[+m[1]]; if (holder.firstElementChild) p.replaceWith(holder.firstElementChild); }
    });

    // task list items → styled boxes
    tmp.querySelectorAll("li").forEach(function (li) {
      var cb = li.querySelector('input[type="checkbox"]');
      if (!cb) return;
      var done = cb.checked;
      li.classList.add("task"); if (done) li.classList.add("done");
      cb.remove();
      var box = document.createElement("span"); box.className = "box"; if (done) box.innerHTML = CHECK;
      li.insertBefore(box, li.firstChild);
    });

    // code fences → mac-dots header
    tmp.querySelectorAll("pre").forEach(function (pre) {
      var code = pre.querySelector("code"); var lang = "";
      if (code) { var c = Array.prototype.find.call(code.classList, function (x) { return x.indexOf("language-") === 0; }); if (c) lang = c.slice(9); }
      var dots = document.createElement("div"); dots.className = "pre-dots";
      dots.innerHTML = '<span class="r"></span><span class="y"></span><span class="g"></span>' + (lang ? '<span class="pre-lang">' + esc(lang) + "</span>" : "");
      pre.insertBefore(dots, pre.firstChild);
    });

    return tmp.innerHTML;
  }

  // ── DOM refs ───────────────────────────────────────────────────────────
  var studioEl, preview, wordCount, srcMeta, saveStatus, saveLabel, editedAt,
    docTitle, historyVersion, viewSeg, revList, revTotal, historyVersionEls,
    hud, hudTime, hudEq, hudCmdText, rccVersion,
    compareBody, cmpChipA, cmpChipB, cmpSwap, cmpSummary, cmpStepLabel,
    cmpPrev, cmpNext, cmpRestore, cmpDone;

  // ── live preview ───────────────────────────────────────────────────────
  var curText = "", lastRendered = null, renderTimer = null, savedTimer = null;

  function scheduleRender() { clearTimeout(renderTimer); renderTimer = setTimeout(doRender, 90); }
  function doRender() {
    if (curText === lastRendered) return;
    lastRendered = curText;
    preview.innerHTML = renderMarkdown(curText);
    var s = stats(curText);
    wordCount.textContent = s.words + " words · ~" + s.mins + " min";
    srcMeta.textContent = "UTF-8 · LF · " + curText.split("\n").length + " ln";
  }
  function markDirty() {
    saveStatus.classList.add("dirty"); saveLabel.textContent = "Saving…";
    if (!IN_APP) { clearTimeout(savedTimer); savedTimer = setTimeout(function () { setSaved(true); }, 500); }
  }
  function setSaved(ok) {
    if (!ok) return;
    saveStatus.classList.remove("dirty");
    saveLabel.textContent = "Saved · autosync";
    editedAt.textContent = "Edited just now";
  }
  function onText(text) { curText = String(text == null ? "" : text); scheduleRender(); markDirty(); }

  // ── format tools (drive the CM6 bridge) ────────────────────────────────
  function selection() { try { return ed().getSelection(); } catch (e) { return { from: 0, to: 0 }; } }
  function docText() { try { return ed().getText(); } catch (e) { return curText; } }
  function lineBounds(t, pos) {
    var start = t.lastIndexOf("\n", pos - 1) + 1;
    var end = t.indexOf("\n", pos); if (end < 0) end = t.length;
    return { start: start, end: end };
  }
  function toggleHeading(level) {
    var t = docText(), s = selection(), b = lineBounds(t, s.from);
    var line = t.slice(b.start, b.end), pfx = new Array(level + 1).join("#") + " ";
    var has = line.indexOf(pfx) === 0;
    line = line.replace(/^#{1,6}\s+/, "");
    ed().replaceRange(b.start, b.end, has ? line : pfx + line); ed().focus();
  }
  function linePrefix(pfx) {
    var t = docText(), s = selection(), b = lineBounds(t, s.from);
    var line = t.slice(b.start, b.end);
    var has = line.indexOf(pfx) === 0;
    line = line.replace(/^([-*+]\s+|\d+\.\s+|>\s+|- \[[ xX]\]\s+)/, "");
    ed().replaceRange(b.start, b.end, has ? line : pfx + line); ed().focus();
  }
  function wrap(before, after) {
    var t = docText(), s = selection(), chosen = t.slice(s.from, s.to);
    if (s.from === s.to) { ed().replaceRange(s.from, s.to, before + after); ed().setSelection(s.from + before.length); }
    else { ed().replaceRange(s.from, s.to, before + chosen + after); ed().setSelection(s.from + before.length, s.to + before.length); }
    ed().focus();
  }
  function makeLink() {
    var t = docText(), s = selection(), chosen = t.slice(s.from, s.to) || "link";
    ed().replaceRange(s.from, s.to, "[" + chosen + "](url)");
    var urlStart = s.from + chosen.length + 3;
    ed().setSelection(urlStart, urlStart + 3); ed().focus();
  }
  var COMMANDS = {
    h1: function () { toggleHeading(1); }, h2: function () { toggleHeading(2); },
    bold: function () { wrap("**", "**"); }, italic: function () { wrap("*", "*"); },
    code: function () { wrap("`", "`"); }, link: makeLink,
    ul: function () { linePrefix("- "); }, ol: function () { linePrefix("1. "); },
    quote: function () { linePrefix("> "); }, task: function () { linePrefix("- [ ] "); }
  };

  // ── view modes ─────────────────────────────────────────────────────────
  var prevMode = "split";
  function setMode(m) {
    if (m !== "compare" && studioEl.dataset.mode === "compare") cmpActive = false;
    if (m !== "compare") prevMode = m;
    studioEl.dataset.mode = m;
    viewSeg.querySelectorAll("button").forEach(function (b) { b.classList.toggle("active", b.dataset.mode === m); });
    try {
      window.dispatchEvent(new Event("resize"));
      if (m === "split" || m === "source") ed().focus();
    } catch (e) { /* noop */ }
  }

  // ── revisions ──────────────────────────────────────────────────────────
  var KIND = {
    dictation: { label: "Dictation", icon: MIC, tone: "acc" },
    voice: { label: "Voice edit", icon: BOLT, tone: "acc" },
    manual: { label: "Manual", icon: PEN, tone: "muted" },
    restore: { label: "Restore", icon: RST, tone: "muted" },
    autoclean: { label: "Auto-clean", icon: SPK, tone: "green" },
    created: { label: "Created", icon: MIC, tone: "acc" }
  };
  function toneColor(tone) { return tone === "green" ? "#3f9b5f" : tone === "muted" ? "var(--faint)" : "var(--acc)"; }
  var revData = null;
  function renderRevItem(r) {
    var k = KIND[r.kind] || KIND.manual;
    var delta = r.delta ? '<span class="r-delta" style="color:' + (r.deltaTone === "green" ? "#3f9b5f" : "var(--faint)") + '">' + esc(r.delta) + "</span>" : "";
    var id = r.id != null ? r.id : r.v;
    return '<div class="rev-item" data-id="' + esc(id) + '" title="Compare this version with Current"><div class="track"><span class="mark" style="background:' + toneColor(k.tone) + '"></span></div>' +
      '<div class="body"><div class="r-top"><span class="r-v">' + esc(r.v) + "</span>" + delta + "</div>" +
      '<div class="r-title">' + esc(r.title || k.label) + "</div>" +
      '<div class="r-foot"><span class="r-badge">' + k.icon + k.label + "</span>" +
      '<span class="r-time">' + esc(r.time || "") + "</span>" +
      '<button class="r-restore" data-id="' + esc(id) + '">Restore</button></div></div></div>';
  }
  function setRevisions(data) {
    data = data || {};
    revData = data;
    var cur = data.current || "v1";
    historyVersion.textContent = cur; rccVersion.textContent = cur;
    revTotal.textContent = (data.total != null ? data.total : (data.items ? data.items.length + 1 : 1)) + " total";
    revList.innerHTML = (data.items || []).map(renderRevItem).join("");
    revList.querySelectorAll(".r-restore").forEach(function (btn) {
      btn.addEventListener("click", function (ev) { ev.stopPropagation(); studioNative({ type: "restore", id: btn.dataset.id }); });
    });
    // Row click compares this version with Current (re-points A while in Compare).
    revList.querySelectorAll(".rev-item").forEach(function (row) {
      row.addEventListener("click", function () {
        if (cmpActive) { cmpA = row.dataset.id; requestCompare(); }
        else openCompare(row.dataset.id, "working");
      });
    });
    if (cmpActive) refreshChips();
  }

  // ── compare (revision diff) ──────────────────────────────────────────────
  var cmpActive = false, cmpA = null, cmpB = "working", cmpPayload = null, changeEls = [], stepIdx = -1;
  var OINS = "", CINS = "", ODEL = "", CDEL = "";

  function revLabel(id) {
    if (id === "working" || id == null) return "Current";
    var items = (revData && revData.items) || [];
    for (var i = 0; i < items.length; i++) { if (String(items[i].id) === String(id)) return items[i].v + " · " + (items[i].time || ""); }
    return "version";
  }
  function refreshChips() {
    if (cmpChipA) cmpChipA.textContent = revLabel(cmpA);
    if (cmpChipB) cmpChipB.textContent = revLabel(cmpB);
    if (cmpRestore) {
      var restorable = cmpA && cmpA !== "working";
      cmpRestore.style.display = restorable ? "" : "none";
      // the button is <svg/> + a trailing text node — retarget just the text
      var short = revLabelShort(cmpA);
      cmpRestore.lastChild.textContent = short ? "Restore " + short : "Restore";
    }
  }
  function revLabelShort(id) {
    if (id === "working") return "";
    var items = (revData && revData.items) || [];
    for (var i = 0; i < items.length; i++) { if (String(items[i].id) === String(id)) return items[i].v; }
    return "";
  }
  function openCompare(aId, bId) {
    cmpActive = true; cmpA = aId; cmpB = bId || "working";
    compareBody.innerHTML = '<div class="compare-empty">Comparing…</div>';
    setMode("compare");
    refreshChips();
    requestCompare();
  }
  function requestCompare() {
    refreshChips();
    if (IN_APP) sendNative({ type: "compare", from: cmpA, to: cmpB });
  }
  function exitCompare() { setMode(prevMode === "compare" ? "split" : prevMode); }
  function swapSides() { var t = cmpA; cmpA = cmpB; cmpB = t; requestCompare(); }

  // merged markdown from word ops, wrapping ins/del runs in PUA sentinels
  function mergedFromWordOps(ops) {
    var out = "", isFirst = true, lastNL = false, cur = "eq";
    function openTag(t) { return t === "ins" ? OINS : t === "del" ? ODEL : ""; }
    function closeTag(t) { return t === "ins" ? CINS : t === "del" ? CDEL : ""; }
    for (var i = 0; i < ops.length; i++) {
      var w = ops[i].w, t = ops[i].t;
      if (w === "\n") { if (cur !== "eq") { out += closeTag(cur); cur = "eq"; } out += "\n"; isFirst = true; lastNL = true; continue; }
      var space = !isFirst && !lastNL;
      if (t !== cur) {
        if (cur !== "eq") out += closeTag(cur);
        if (space) { out += " "; space = false; }
        if (t !== "eq") out += openTag(t);
        cur = t;
      } else if (space) { out += " "; }
      out += w; isFirst = false; lastNL = false;
    }
    if (cur !== "eq") out += closeTag(cur);
    return out;
  }
  function unsentinel(html) {
    return html.split(OINS).join('<mark class="rev-ins">').split(CINS).join("</mark>")
      .split(ODEL).join('<del class="rev-del">').split(CDEL).join("</del>");
  }
  function badgeKind(kind) { return kind === "dictation" || kind === "memo" || kind === "code" || kind === "table"; }
  var GUT = { added: "+", removed: "−", changed: "~", eq: "" };  // − is U+2212

  // one diff row: [gutter glyph] | [rendered content]
  function segRow(status, kind, inner) {
    return '<div class="rev-seg ' + status + '" data-kind="' + esc(kind) + '">' +
      '<div class="seg-gutter" aria-hidden="true">' + (GUT[status] || "") + "</div>" +
      '<div class="seg-content">' + inner + "</div></div>";
  }

  function renderSegment(seg) {
    var status = seg.status, kind = seg.kind || "other";
    if (status === "equal") return segRow("eq", kind, renderMarkdown(seg.b || ""));

    var badge = "";
    if (badgeKind(kind)) {
      var label = status === "added" ? "Added" : status === "removed" ? "Removed" : "Edited";
      badge = '<span class="seg-badge">' + label + "</span>";
    }
    if (status === "added") return segRow("added", kind, badge + renderMarkdown(seg.b || ""));
    if (status === "removed") return segRow("removed", kind, badge + renderMarkdown(seg.a || ""));

    // changed
    if (seg.wordOps && seg.wordOps.length) {
      var changedCount = 0;
      for (var i = 0; i < seg.wordOps.length; i++) if (seg.wordOps[i].t !== "eq") changedCount++;
      var churn = seg.wordOps.length ? changedCount / seg.wordOps.length : 0;
      if (churn > 0.6) {
        // too churned to word-dice — stack removed above added
        return segRow("removed", kind, renderMarkdown(seg.a || "")) +
          segRow("added", kind, renderMarkdown(seg.b || ""));
      }
      return segRow("changed", kind, unsentinel(renderMarkdown(mergedFromWordOps(seg.wordOps))));
    }
    // atomic changed (dictation / memo / code / table) — show the new one, badged
    return segRow("changed", kind, badge + renderMarkdown(seg.b || seg.a || ""));
  }

  function setCompare(payload) {
    cmpPayload = payload || {};
    if (payload && payload.from != null) cmpA = payload.from;
    if (payload && payload.to != null) cmpB = payload.to;
    refreshChips();
    var segs = (payload && payload.segments) || [];
    if (payload && payload.identical) {
      compareBody.innerHTML = '<div class="compare-empty">These two versions are identical.</div>';
    } else {
      compareBody.innerHTML = segs.map(renderSegment).join("");
    }
    var st = (payload && payload.stats) || { added: 0, removed: 0, changed: 0 };
    cmpSummary.textContent = st.added + " added · " + st.changed + " changed · " + st.removed + " removed";
    // build change list for the stepper
    changeEls = Array.prototype.slice.call(compareBody.querySelectorAll(".rev-seg.added, .rev-seg.removed, .rev-seg.changed"));
    stepIdx = -1;
    updateStepper();
  }
  function updateStepper() {
    var n = changeEls.length;
    cmpStepLabel.textContent = n === 0 ? "no changes" : (stepIdx < 0 ? n + " changes" : (stepIdx + 1) + " of " + n);
    cmpPrev.disabled = n === 0 || stepIdx <= 0;
    cmpNext.disabled = n === 0 || stepIdx >= n - 1;
  }
  function stepChange(dir) {
    if (!changeEls.length) return;
    stepIdx = Math.max(0, Math.min(changeEls.length - 1, (stepIdx < 0 ? (dir > 0 ? 0 : changeEls.length - 1) : stepIdx + dir)));
    var el = changeEls[stepIdx];
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    el.classList.remove("pulse"); void el.offsetWidth; el.classList.add("pulse");
    updateStepper();
  }

  // ── dictation (real: Swift owns record → transcribe → insert) ───────────
  // dictState: idle | starting | listening | transcribing (error resets to idle)
  var dictState = "idle", dictMode = "prose", eqTick = 0, errTimer = null, dictAvailable = true;

  function buildEq() {
    hudEq.innerHTML = "";
    for (var i = 0; i < 30; i++) {
      var s = document.createElement("span");
      s.style.animationDelay = ((i % 9) * 0.07 + i * 0.012).toFixed(2) + "s";
      hudEq.appendChild(s);
    }
  }
  function paintEq(level) {
    var bars = hudEq.children;
    for (var i = 0; i < bars.length; i++) {
      var env = 0.35 + 0.65 * Math.sin((i / (bars.length - 1)) * Math.PI); // center-weighted
      var wobble = 0.55 + 0.45 * Math.abs(Math.sin(eqTick * 0.35 + i * 0.7));
      var v = Math.max(0.12, Math.min(1, (0.14 + 0.86 * level) * env * wobble));
      bars[i].style.transform = "scaleY(" + v.toFixed(3) + ")";
    }
  }

  // Requested by the buttons/HUD; Swift drives the lifecycle back via
  // setDictationState / setDictationLevel. Browser dev falls back to a sim.
  function requestDictate(mode) {
    if (!dictAvailable) return;
    if (dictState === "listening") { stopDictate(); return; }
    if (dictState !== "idle") return;   // starting / transcribing — ignore
    dictMode = mode;
    if (IN_APP) { sendNative({ type: "dictate", mode: mode }); }
    else { browserDictateSim(mode); }
    try { ed().focus(); } catch (e) { /* noop */ }
  }
  function stopDictate() {
    if (dictState !== "listening") return;
    if (IN_APP) { sendNative({ type: "dictateStop" }); }
    else { browserStopSim(); }
  }

  // Blockify — promote the current selection (or line) into a memo block.
  function blockifySelection() {
    var t = docText(), s = selection(), from = s.from, to = s.to;
    if (from === to) { var b = lineBounds(t, from); from = b.start; to = b.end; }
    var chosen = t.slice(from, to).trim();
    if (!chosen) return;
    var id = "tkm_" + Math.random().toString(36).slice(2, 10);
    var before = from > 0 && t[from - 1] !== "\n" ? "\n\n" : "";
    var after = to < t.length && t[to] !== "\n" ? "\n\n" : "";
    var block = before + '::: memo id="' + id + '"\n' + chosen + "\n:::" + after;
    ed().replaceRange(from, to, block); ed().focus();
  }

  // Swift → studio: HUD lifecycle.
  function setDictationState(state, opts) {
    opts = opts || {};
    if (opts.mode) dictMode = opts.mode;
    clearTimeout(errTimer);

    if (state === "error") {
      dictState = "idle"; studioEl.classList.remove("dictating");
      hudEq.classList.remove("live");
      hud.hidden = false; hud.dataset.state = "error";
      hudCmdText.textContent = opts.message ? String(opts.message) : "dictation failed";
      errTimer = setTimeout(function () { hud.hidden = true; hud.dataset.state = ""; }, 2400);
      return;
    }
    if (state === "idle") {
      dictState = "idle"; studioEl.classList.remove("dictating");
      hudEq.classList.remove("live"); hud.hidden = true; hud.dataset.state = "";
      return;
    }
    // starting | listening | transcribing — keep the cluster locked throughout
    dictState = state;
    studioEl.classList.add("dictating");
    hud.hidden = false; hud.dataset.state = state;
    if (!hudEq.children.length) buildEq();
    hudEq.classList.add("live");
    if (state === "starting") { hudTime.textContent = "00:00"; hudCmdText.textContent = "starting…"; }
    else if (state === "transcribing") { hudCmdText.textContent = "transcribing…"; }
    else { hudCmdText.textContent = dictMode === "block" ? "recording block" : "dictating"; }
  }

  // Swift → studio: live meter (~20 Hz).
  function setDictationLevel(level, elapsedMs) {
    hudTime.textContent = fmtTime(Math.floor((elapsedMs || 0) / 1000));
    eqTick++;
    paintEq(Math.max(0, Math.min(1, level || 0)));
  }

  function setDictationAvailable(ok) {
    dictAvailable = !!ok;
    studioEl.dataset.dictation = ok ? "on" : "off";
  }

  // ── browser dev simulation (page runs standalone) ───────────────────────
  var simLevelTimer = null, simSecs = 0;
  function browserDictateSim(mode) {
    setDictationState("listening", { mode: mode });
    simSecs = 0;
    simLevelTimer = setInterval(function () {
      simSecs += 0.05;
      setDictationLevel(0.28 + 0.5 * Math.abs(Math.sin(simSecs * 3.2)), simSecs * 1000);
    }, 50);
  }
  function browserStopSim() {
    clearInterval(simLevelTimer);
    setDictationState("transcribing", { mode: dictMode });
    setTimeout(function () {
      var demo = "This is a simulated dictation for browser preview.";
      try {
        if (dictMode === "block") {
          ed().insertTextAtCursor('\n\n::: dictation title="browser-demo" duration="0:05" words="8"\n' + demo + "\n:::\n\n");
        } else { ed().insertTextAtCursor(" " + demo); }
      } catch (e) { /* noop */ }
      setDictationState("idle", {});
    }, 550);
  }

  // ── studio → native (in-app: Swift persists; browser: local sim) ────────
  var localRevs = null;
  function studioNative(msg) {
    if (IN_APP) { sendNative(msg); return; }
    // browser dev simulation
    if (!localRevs) localRevs = { current: "v1", total: 1, items: [] };
    if (msg.type === "saveVersion") {
      var n = (localRevs.total || 1) + 1;
      localRevs.items.unshift({ v: localRevs.current, id: localRevs.current, kind: msg.reason === "dictation" ? "dictation" : "manual", title: msg.reason === "dictation" ? "Dictation inserted" : "Saved version", time: "just now", delta: "", snapshot: curText });
      localRevs.current = "v" + n; localRevs.total = n;
      setRevisions(localRevs); setSaved(true);
    } else if (msg.type === "restore") {
      var hit = (localRevs.items || []).filter(function (r) { return String(r.id) === String(msg.id); })[0];
      if (hit && hit.snapshot != null) { try { ed().setText(hit.snapshot); } catch (e) { /* noop */ } }
    }
  }

  // ── public API for Swift ───────────────────────────────────────────────
  window.TalkieStudio = {
    onText: onText,
    setRevisions: setRevisions,
    setSaved: setSaved,
    setMode: setMode,
    setDictationState: setDictationState,
    setDictationLevel: setDictationLevel,
    setDictationAvailable: setDictationAvailable,
    setCompare: setCompare,
    setDocTitle: function (t) { if (docTitle) docTitle.textContent = t; },
    setEditedLabel: function (t) { if (editedAt) editedAt.textContent = t; }
  };

  // ── browser stub: route editor.js posts here + seed a sample doc ────────
  var SEED = [
    "# Home screen — redesign notes", "",
    "Captured by voice · May 27 · cleaned up with Talkie", "",
    "## What's working", "",
    "The **agent bar** finally reads like an instrument — the amber trace draws the eye first.", "",
    '::: dictation title="shelf-and-sheet" duration="0:24" words="61"',
    "I like the shelf and the sheet — basically the sheet with the list of names, and room to breathe on the right.",
    ":::", "",
    "- Empty states feel *inviting*, not empty",
    "- Recent has room to breathe",
    "- Waveforms are duration-accurate now", "",
    "## Still open", "",
    "1. Should the console live in its own tab?",
    "2. Tighten the tips row on small windows", "",
    "> \"Talk, it moves.\" Keep the whole thing this quiet", "",
    "Reference the [style guide](#) first. Then run:", "",
    "```bash", "talkie export --home > notes.md", "```", "",
    "## Next steps", "",
    "- [x] Ship the agent bar",
    "- [x] Warm up the empty states",
    "- [ ] Decide console-in-tab",
    "- [ ] Tips row responsive pass", "",
    "---", "",
    "### Signal check", "",
    "How the redesign scored, screen by screen.", "",
    "| Screen | Before | After |",
    "| --- | --- | --- |",
    "| Home | 3.1 | 4.6 |",
    "| Editor | — | 4.8 |"
  ].join("\n");

  function handleEditorMessage(m) {
    if (!m || !m.type) return;
    if (m.type === "ready") {
      try { ed().configure({ accentColor: "#c47d1c", textColor: "#4a3f31", fontSize: 13, lineHeight: 1.92 }); } catch (e) { /* noop */ }
      try { ed().setText(SEED); } catch (e) { /* noop */ }
      setRevisions({ current: "v1", total: 1, items: [] });
    } else if (m.type === "change") { onText(m.text); }
  }
  if (!IN_APP) {
    window.webkit = { messageHandlers: { talkieEditor: { postMessage: handleEditorMessage } } };
  }

  // ── boot ───────────────────────────────────────────────────────────────
  function boot() {
    studioEl = $("studio"); preview = $("preview"); wordCount = $("wordCount");
    srcMeta = $("srcMeta"); saveStatus = $("saveStatus"); saveLabel = $("saveLabel");
    editedAt = $("editedAt"); docTitle = $("docTitle"); historyVersion = $("historyVersion");
    viewSeg = $("viewSeg"); revList = $("revList"); revTotal = $("revTotal");
    hud = $("hud"); hudTime = $("hudTime"); hudEq = $("hudEq"); hudCmdText = $("hudCmdText");
    rccVersion = $("rccVersion");
    compareBody = $("compareBody"); cmpChipA = $("cmpChipA"); cmpChipB = $("cmpChipB");
    cmpSwap = $("cmpSwap"); cmpSummary = $("cmpSummary"); cmpStepLabel = $("cmpStepLabel");
    cmpPrev = $("cmpPrev"); cmpNext = $("cmpNext"); cmpRestore = $("cmpRestore"); cmpDone = $("cmpDone");

    // view modes
    viewSeg.querySelectorAll("button").forEach(function (b) { b.addEventListener("click", function () { setMode(b.dataset.mode); }); });
    // history toggle
    $("historyBtn").addEventListener("click", function () {
      studioEl.dataset.revisions = studioEl.dataset.revisions === "open" ? "closed" : "open";
    });
    // format tools
    $("formatGroup").querySelectorAll(".fmt").forEach(function (b) {
      b.addEventListener("click", function (ev) { ev.preventDefault(); var fn = COMMANDS[b.dataset.cmd]; if (fn) fn(); });
    });
    // dictation
    $("dictateBtn").addEventListener("click", function () { requestDictate("prose"); });
    $("dictateBlockBtn").addEventListener("click", function () { requestDictate("block"); });
    $("blockifyBtn").addEventListener("click", blockifySelection);
    $("hudStop").addEventListener("click", stopDictate);
    // revisions actions
    $("saveVersionBtn").addEventListener("click", function () { studioNative({ type: "saveVersion", reason: "manual" }); });
    // compare: current-card Compare = newest earlier version vs Current
    $("compareBtn").addEventListener("click", function () {
      var items = (revData && revData.items) || [];
      if (!items.length) return;
      openCompare(items[0].id, "working");
    });
    cmpSwap.addEventListener("click", swapSides);
    cmpPrev.addEventListener("click", function () { stepChange(-1); });
    cmpNext.addEventListener("click", function () { stepChange(1); });
    cmpDone.addEventListener("click", exitCompare);
    cmpRestore.addEventListener("click", function () {
      if (cmpA && cmpA !== "working") { studioNative({ type: "restore", id: cmpA }); exitCompare(); }
    });

    // keyboard shortcuts (CM6 owns ⌘Z/⌘⇧Z; we add ⌘B/⌘I/⌘K)
    document.addEventListener("keydown", function (e) {
      // compare navigation (read-only view — bare keys are safe)
      if (cmpActive && !(e.metaKey || e.ctrlKey || e.altKey)) {
        var kk = e.key.toLowerCase();
        if (e.key === "Escape") { e.preventDefault(); exitCompare(); return; }
        if (kk === "n" || e.key === "ArrowDown") { e.preventDefault(); stepChange(1); return; }
        if (kk === "p" || e.key === "ArrowUp") { e.preventDefault(); stepChange(-1); return; }
      }
      if (!(e.metaKey || e.ctrlKey) || e.altKey) return;
      var k = e.key.toLowerCase(), fn = null;
      if (k === "b") fn = COMMANDS.bold; else if (k === "i") fn = COMMANDS.italic; else if (k === "k") fn = COMMANDS.link;
      if (fn) { e.preventDefault(); fn(); }
    });

    // safety: if Swift set text but never forwarded, pull it directly
    [300, 900].forEach(function (d) { setTimeout(function () { try { var t = ed().getText(); if (t && t !== lastRendered) onText(t); } catch (e) { /* noop */ } }, d); });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
