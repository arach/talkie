const bridge = window.webkit?.messageHandlers?.talkieExport;

const els = {};
const state = {
  title: "Capture",
  sourceDataURL: "",
  sourceWidth: 0,
  sourceHeight: 0,
  sourceBytes: "",
  sourceLabel: "",
  suggestedName: "Talkie Export",
  preset: "polished",
  background: "paper",
  padding: 48,
  radius: 18,
  shadow: 24,
  format: "png",
  quality: 0.92,
  scale: 1
};

const presets = {
  original: {
    background: "none",
    padding: 0,
    radius: 0,
    shadow: 0,
    format: "png",
    quality: 0.92,
    scale: 1
  },
  polished: {
    background: "paper",
    padding: 48,
    radius: 18,
    shadow: 24,
    format: "png",
    quality: 0.92,
    scale: 1
  }
};

const backgrounds = {
  none: "transparent",
  paper: "#f7f3e9",
  graphite: "#222629",
  amber: "#e8d1a5"
};

function post(type, payload = {}) {
  if (!bridge) {
    console.log("talkieExport", type, payload);
    return;
  }
  bridge.postMessage({ type, ...payload });
}

function cacheElements() {
  [
    "captureTitle", "closeButton", "previewMat", "imageShell", "sourceImage",
    "sourceReadout", "exportReadout", "paddingInput", "paddingValue",
    "radiusInput", "radiusValue", "shadowInput", "shadowValue",
    "qualityInput", "qualityValue", "scaleInput", "copyButton", "saveButton"
  ].forEach((id) => {
    els[id] = document.getElementById(id);
  });
}

function bindControls() {
  document.querySelectorAll("[data-preset]").forEach((button) => {
    button.addEventListener("click", () => applyPreset(button.dataset.preset));
  });

  document.querySelectorAll("[data-background]").forEach((button) => {
    button.addEventListener("click", () => {
      state.background = button.dataset.background;
      state.preset = "custom";
      render();
    });
  });

  document.querySelectorAll("[data-format]").forEach((button) => {
    button.addEventListener("click", () => {
      state.format = button.dataset.format;
      state.preset = "custom";
      render();
    });
  });

  els.paddingInput.addEventListener("input", () => {
    state.padding = Number(els.paddingInput.value);
    state.preset = "custom";
    render();
  });

  els.radiusInput.addEventListener("input", () => {
    state.radius = Number(els.radiusInput.value);
    state.preset = "custom";
    render();
  });

  els.shadowInput.addEventListener("input", () => {
    state.shadow = Number(els.shadowInput.value);
    state.preset = "custom";
    render();
  });

  els.qualityInput.addEventListener("input", () => {
    state.quality = Number(els.qualityInput.value) / 100;
    state.preset = "custom";
    render();
  });

  els.scaleInput.addEventListener("change", () => {
    state.scale = Number(els.scaleInput.value);
    state.preset = "custom";
    render();
  });

  els.copyButton.addEventListener("click", () => exportArtifact("export.copy"));
  els.saveButton.addEventListener("click", () => exportArtifact("export.save"));
  els.closeButton.addEventListener("click", () => post("export.close"));
}

function init(payload) {
  state.title = payload.title || "Capture";
  state.sourceDataURL = payload.imageDataURL || "";
  state.sourceWidth = payload.width || 0;
  state.sourceHeight = payload.height || 0;
  state.sourceBytes = payload.fileSize || "";
  state.sourceLabel = payload.sourceLabel || "";
  state.suggestedName = payload.suggestedName || state.title || "Talkie Export";

  els.captureTitle.textContent = state.title;
  els.sourceImage.src = state.sourceDataURL;
  els.sourceImage.onload = render;
  render();
}

function applyPreset(name) {
  if (!presets[name]) { return; }
  Object.assign(state, presets[name]);
  state.preset = name;
  render();
}

function syncControls() {
  document.querySelectorAll("[data-preset]").forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === state.preset);
  });
  document.querySelectorAll("[data-background]").forEach((button) => {
    button.classList.toggle("active", button.dataset.background === state.background);
  });
  document.querySelectorAll("[data-format]").forEach((button) => {
    button.classList.toggle("active", button.dataset.format === state.format);
  });

  els.paddingInput.value = state.padding;
  els.paddingValue.textContent = String(state.padding);
  els.radiusInput.value = state.radius;
  els.radiusValue.textContent = String(state.radius);
  els.shadowInput.value = state.shadow;
  els.shadowValue.textContent = String(state.shadow);
  els.qualityInput.value = Math.round(state.quality * 100);
  els.qualityValue.textContent = `${Math.round(state.quality * 100)}%`;
  els.scaleInput.value = String(state.scale);
  els.qualityInput.disabled = state.format !== "jpeg";
}

function render() {
  syncControls();

  const mat = els.previewMat;
  const shell = els.imageShell;
  mat.dataset.bg = state.background;
  mat.style.padding = `${state.padding}px`;
  mat.style.borderRadius = `${Math.max(0, state.radius + Math.min(20, state.padding / 2))}px`;

  shell.style.borderRadius = `${state.radius}px`;
  shell.style.boxShadow = state.shadow > 0
    ? `0 ${Math.round(state.shadow * 0.45)}px ${state.shadow}px rgba(26, 29, 31, 0.24)`
    : "none";

  const width = sourceWidth();
  const height = sourceHeight();
  const exportWidth = Math.round((width + state.padding * 2) * state.scale);
  const exportHeight = Math.round((height + state.padding * 2) * state.scale);
  const format = state.format === "jpeg" ? "JPEG" : "PNG";
  els.sourceReadout.textContent = [
    state.sourceLabel,
    width && height ? `${width} x ${height}` : "",
    state.sourceBytes
  ].filter(Boolean).join(" / ");
  els.exportReadout.textContent = `${format} / ${exportWidth} x ${exportHeight}`;
}

function sourceWidth() {
  return els.sourceImage.naturalWidth || state.sourceWidth || 0;
}

function sourceHeight() {
  return els.sourceImage.naturalHeight || state.sourceHeight || 0;
}

async function exportArtifact(type) {
  try {
    const dataURL = await renderCanvas();
    post(type, {
      dataURL,
      format: state.format,
      suggestedName: state.suggestedName,
      width: Math.round((sourceWidth() + state.padding * 2) * state.scale),
      height: Math.round((sourceHeight() + state.padding * 2) * state.scale)
    });
  } catch (error) {
    post("export.error", { message: error?.message || "Export failed" });
  }
}

function ensureImageReady() {
  if (els.sourceImage.complete && sourceWidth() > 0) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    els.sourceImage.onload = () => resolve();
    els.sourceImage.onerror = () => reject(new Error("The capture could not be loaded."));
  });
}

async function renderCanvas() {
  await ensureImageReady();

  const img = els.sourceImage;
  const width = sourceWidth();
  const height = sourceHeight();
  const scale = Math.max(1, Number(state.scale) || 1);
  const cssWidth = Math.max(1, width + state.padding * 2);
  const cssHeight = Math.max(1, height + state.padding * 2);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(cssWidth * scale);
  canvas.height = Math.round(cssHeight * scale);

  const ctx = canvas.getContext("2d");
  ctx.scale(scale, scale);

  const bg = backgrounds[state.background] || backgrounds.paper;
  if (state.background !== "none" || state.format === "jpeg") {
    ctx.fillStyle = state.background === "none" ? "#ffffff" : bg;
    ctx.fillRect(0, 0, cssWidth, cssHeight);
  }

  const x = state.padding;
  const y = state.padding;
  const radius = Math.min(state.radius, width / 2, height / 2);

  if (state.shadow > 0) {
    ctx.save();
    ctx.shadowColor = "rgba(24, 28, 31, 0.28)";
    ctx.shadowBlur = state.shadow;
    ctx.shadowOffsetY = state.shadow * 0.42;
    roundedRect(ctx, x, y, width, height, radius);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    ctx.restore();
  }

  ctx.save();
  roundedRect(ctx, x, y, width, height, radius);
  ctx.clip();
  ctx.drawImage(img, x, y, width, height);
  ctx.restore();

  const mime = state.format === "jpeg" ? "image/jpeg" : "image/png";
  return canvas.toDataURL(mime, state.quality);
}

function roundedRect(ctx, x, y, width, height, radius) {
  const r = Math.max(0, Math.min(radius, width / 2, height / 2));
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + width - r, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + r);
  ctx.lineTo(x + width, y + height - r);
  ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
  ctx.lineTo(x + r, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

window.talkieExport = { init };

document.addEventListener("DOMContentLoaded", () => {
  cacheElements();
  bindControls();
  post("export.ready");
});
