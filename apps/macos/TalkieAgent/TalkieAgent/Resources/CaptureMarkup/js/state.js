(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function createMarkupState(initialContext) {
    return {
      tool: "ink",
      mode: "agent",
      color: "#D03A1C",
      strokeWidth: 4,
      noteStyle: "sticky",
      lineStyle: "solid",
      fillStyle: "wash",
      arrowStyle: "straight",
      pointerStyle: "open",
      styleOpen: false,
      context: initialContext,
      layers: [],
      redoStack: [],
      creating: null,
      noteEditor: null,
      selectedLayerId: null,
      dragging: null,
      materialBackdrops: new Map(),
      materialRequests: new Map(),
      latestMaterialRequestByLayer: new Map(),
      materialRequestSequence: 0,
      drawableRect: null,
      lastPointer: { x: 0.5, y: 0.5 },
      startedAt: performance.now(),
    };
  }

  function nowSeconds(state) {
    return Math.max(0, (performance.now() - state.startedAt) / 1000);
  }

  function uuid() {
    if (window.crypto && window.crypto.randomUUID) {
      return window.crypto.randomUUID();
    }
    return "layer-" + Math.random().toString(16).slice(2) + Date.now().toString(16);
  }

  function cloneLayer(layer) {
    return JSON.parse(JSON.stringify(layer));
  }

  root.State = {
    createMarkupState,
    nowSeconds,
    uuid,
    cloneLayer,
  };
})();
