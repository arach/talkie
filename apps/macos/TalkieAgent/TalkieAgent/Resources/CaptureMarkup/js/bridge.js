(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function post(name, payload = {}) {
    const handler = window.webkit
      && window.webkit.messageHandlers
      && window.webkit.messageHandlers.talkie;
    if (!handler) return;
    handler.postMessage(Object.assign({ name }, payload));
  }

  function installAPI(api) {
    window.talkieLiveMarkup = api;
    return api;
  }

  root.Bridge = {
    post,
    installAPI,
  };
})();
