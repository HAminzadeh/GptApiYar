// GptApiYar Smart Connector v1. Connects ONLY the local demo; never reads ChatGPT.
const GATEWAY = 'http://127.0.0.1:8787';
const DEMO = GATEWAY + '/demo.html';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function trustedSender(sender) {
  try {
    const url = new URL(sender.url || '');
    return url.origin === 'http://127.0.0.1:5173' && sender.tab &&
      sender.tab.url && new URL(sender.tab.url).origin === url.origin;
  } catch { return false; }
}

async function probe(token) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4500);
  try {
    const response = await fetch(GATEWAY + '/api/extension/status', {
      headers: {'X-Gateway-Token': token},
      cache: 'no-store', signal: controller.signal
    });
    if (response.status === 401) throw new Error('توکن درست نیست؛ مقدار React و Spring Boot باید یکسان باشد.');
    if (!response.ok) throw new Error('Spring Boot HTTP ' + response.status);
    const body = await response.json();
    if (body.mode !== 'extension') throw new Error('نسخه بک‌اند از اتصال افزونه پشتیبانی نمی‌کند.');
    return body;
  } catch (error) {
    if (error.name === 'AbortError') throw new Error('مهلت ارتباط با Spring Boot به پایان رسید.');
    if (error instanceof TypeError) throw new Error('Spring Boot روی پورت 8787 در دسترس نیست.');
    throw error;
  } finally { clearTimeout(timeout); }
}

async function getDemoTab() {
  const tabs = await chrome.tabs.query({url: 'http://127.0.0.1/*'});
  const existing = tabs.find(t => t.url === DEMO);
  if (existing) return existing;
  // User clicked the connect button. Only a new TAB in the existing Chrome is opened.
  return await chrome.tabs.create({url: DEMO, active: true});
}

async function ensureContentScript(tabId) {
  for (let attempt = 0; attempt < 24; attempt++) {
    try {
      const state = await chrome.tabs.sendMessage(tabId, {type: 'gptapiyar-status'});
      if (state && typeof state.enabled === 'boolean') return;
    } catch (_) { /* Tab may still be loading or running an older content script. */ }
    if (attempt === 6) await chrome.tabs.reload(tabId);
    await sleep(400);
  }
  throw new Error('اسکریپت افزونه در تب آماده نشد. افزونه را Reload و تب demo.html را Refresh کن.');
}

async function connect({url, token}) {
  if (url !== DEMO) throw new Error('این نسخه فقط برای http://127.0.0.1:8787/demo.html فعال است.');
  if (typeof token !== 'string' || token.length < 4 || token.length > 512) {
    throw new Error('توکن محلی نامعتبر است.');
  }
  await probe(token);
  const tab = await getDemoTab();
  await ensureContentScript(tab.id);
  const accepted = await chrome.tabs.sendMessage(tab.id, {type: 'gptapiyar-connect', token});
  if (!accepted?.ok) throw new Error(accepted?.message || 'فعال‌سازی تب ناموفق بود.');
  await chrome.storage.local.set({gatewayToken: token});
  for (let attempt = 0; attempt < 20; attempt++) {
    await sleep(350);
    const result = await probe(token);
    if (result.connected && result.pageUrl === DEMO) {
      return {ok: true, title: result.title || tab.title || 'Local demo', url: DEMO};
    }
  }
  const state = await chrome.tabs.sendMessage(tab.id, {type: 'gptapiyar-status'}).catch(() => ({}));
  throw new Error('تب فعال شد ولی سرور heartbeat دریافت نکرد. ' + (state.lastError || 'توکن یا اتصال محلی را بررسی کن.'));
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!trustedSender(sender) || message?.type !== 'gptapiyar-smart-connect') return false;
  connect(message)
    .then(result => sendResponse(result))
    .catch(error => sendResponse({ok: false, error: String(error.message || error)}));
  return true;
});