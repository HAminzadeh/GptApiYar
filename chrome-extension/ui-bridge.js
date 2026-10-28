// GptApiYar Smart Connector v1: localhost UI bridge only.
(() => {
  if (location.origin !== 'http://127.0.0.1:5173') return;
  const ORIGIN = location.origin;
  const UI = 'gptapiyar-web';
  const EXTENSION = 'gptapiyar-extension-ui';
  const reply = data => window.postMessage({source: EXTENSION, ...data}, ORIGIN);
  reply({type: 'ready'});

  window.addEventListener('message', async event => {
    if (event.source !== window || event.origin !== ORIGIN) return;
    const request = event.data;
    if (!request || request.source !== UI || request.type !== 'request') return;
    if (typeof request.requestId !== 'string' || request.requestId.length > 100) return;
    if (request.action === 'ping') {
      reply({type: 'pong', requestId: request.requestId});
      return;
    }
    if (request.action !== 'connect') return;
    let result;
    try {
      result = await chrome.runtime.sendMessage({
        type: 'gptapiyar-smart-connect',
        url: request.url,
        token: request.token
      });
      if (!result) throw new Error('No response from extension background service worker');
    } catch (error) {
      result = {ok: false, error: String(error.message || error)};
    }
    reply({type: 'result', requestId: request.requestId, result});
  });
})();