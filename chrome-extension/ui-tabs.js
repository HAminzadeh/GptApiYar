// GptApiYar browser tab list bridge. Only active on the local React page.
(() => {
  if (location.origin !== 'http://127.0.0.1:5173' && location.origin !== 'http://localhost:5173') return;
  const origin = location.origin;
  const pageSource = 'gptapiyar-tabs-web';
  const extSource = 'gptapiyar-tabs-extension';
  const reply = data => window.postMessage({source: extSource, ...data}, origin);
  reply({type: 'ready'});
  window.addEventListener('message', async event => {
    if (event.source !== window || event.origin !== origin) return;
    const m = event.data;
    if (!m || m.source !== pageSource) return;
    if (m.type === 'ping') { reply({type: 'ready'}); return; }
    if (m.type !== 'request' || typeof m.requestId !== 'string' || m.requestId.length > 100) return;
    if (!['list', 'select', 'focus'].includes(m.action)) return;
    let result;
    try {
      result = await chrome.runtime.sendMessage({
        type: 'gptapiyar-tabs', action: m.action,
        tabId: ['select', 'focus'].includes(m.action) ? Number(m.tabId) : undefined,
        token: m.action === 'select' ? String(m.token || '') : undefined
      });
      if (!result) throw new Error('No response from the extension service worker');
    } catch (error) {
      result = {ok: false, error: String(error?.message || error)};
    }
    reply({type: 'result', requestId: m.requestId, result});
  });
})();
