// Restricted to GptApiYar's own demo.html by manifest. Never runs on ChatGPT.
(() => {
  if (location.origin !== 'http://127.0.0.1:8787' || location.pathname !== '/demo.html') return;
  let enabled = false;
  let token = '';
  let busy = false;
  let sessionId = crypto.randomUUID();
  const base = 'http://127.0.0.1:8787/api/extension';

  chrome.runtime.onMessage.addListener((message, sender, reply) => {
    if (message?.type === 'gptapiyar-connect') {
      token = String(message.token || '');
      enabled = token.length > 0;
      sessionId = crypto.randomUUID();
      reply({ok: enabled, message: enabled ? 'Local demo connector activated' : 'Token is required'});
    }
    if (message?.type === 'gptapiyar-disconnect') {
      enabled = false;
      reply({ok: true});
    }
  });

  async function api(path, data) {
    const response = await fetch(base + path, {
      method: 'POST',
      headers: {'X-Gateway-Token': token, 'Content-Type': 'application/json'},
      body: JSON.stringify(data),
      cache: 'no-store'
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
    return payload;
  }

  async function runDemo(message) {
    const input = document.querySelector('#demo-prompt');
    const send = document.querySelector('#demo-send');
    if (!input || !send) throw new Error('Demo input or send button not found');
    const previousCount = document.querySelectorAll('.demo-message.assistant').length;
    input.value = message;
    input.dispatchEvent(new Event('input', {bubbles: true}));
    send.click();
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 200));
      const responses = document.querySelectorAll('.demo-message.assistant');
      const busyIndicator = document.querySelector('#demo-busy');
      if (responses.length > previousCount &&
          (!busyIndicator || getComputedStyle(busyIndicator).display === 'none')) {
        return (responses[responses.length - 1].textContent || '').trim();
      }
    }
    throw new Error('Timed out waiting for a demo response');
  }

  async function tick() {
    if (!enabled || busy) return;
    busy = true;
    try {
      const job = await api('/poll', {sessionId, pageUrl: location.href, title: document.title});
      if (job.id) {
        try {
          const response = await runDemo(job.message || '');
          await api('/result', {sessionId, jobId: job.id, message: response, error: ''});
        } catch (err) {
          await api('/result', {sessionId, jobId: job.id, message: '', error: String(err.message || err)});
        }
      }
    } catch (err) {
      // Fail closed: a wrong local token must never repeatedly send privileged requests.
      if (String(err.message).includes('401')) enabled = false;
      console.debug('[GptApiYar] Bridge poll:', err.message || err);
    } finally { busy = false; }
  }
  setInterval(tick, 1000);
})();
