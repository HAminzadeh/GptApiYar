// GptApiYar Tab Registry: metadata-only for other sites; full chat only on local demo.
(() => {
  const DEMO = 'http://127.0.0.1:8787/demo.html';
  const ORIGINS = new Set(['http://127.0.0.1:5173', 'http://localhost:5173']);
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

  function trusted(sender) {
    try {
      const source = new URL(sender.url || '');
      const tab = new URL(sender.tab?.url || '');
      return ORIGINS.has(source.origin) && source.origin === tab.origin;
    } catch { return false; }
  }
  function isDemo(url) {
    try {
      const u = new URL(url || '');
      return u.origin === 'http://127.0.0.1:8787' && u.pathname === '/demo.html' && !u.search;
    } catch { return false; }
  }
  function info(tab) {
    const url = String(tab.url || tab.pendingUrl || '');
    let displayUrl = url;
    let kind = 'restricted';
    try {
      const u = new URL(url);
      if (u.protocol === 'http:' || u.protocol === 'https:') {
        // Do not copy query strings, fragments or embedded credentials into React.
        displayUrl = u.origin + u.pathname;
        kind = isDemo(url) ? 'demo' : 'website';
      }
    } catch { displayUrl = url.slice(0, 180); }
    return {
      id: tab.id, windowId: tab.windowId,
      title: String(tab.title || 'بدون عنوان').slice(0, 140),
      url: displayUrl.slice(0, 350), kind, active: Boolean(tab.active),
      connected: false
    };
  }
  async function probe(token) {
    if (typeof token !== 'string' || token.length < 4 || token.length > 512) {
      throw new Error('توکن محلی صحیح نیست.');
    }
    let response;
    try {
      response = await fetch('http://127.0.0.1:8787/api/extension/status', {
        headers: {'X-Gateway-Token': token}, cache: 'no-store',
        signal: AbortSignal.timeout(5000)
      });
    } catch { throw new Error('Spring Boot روی پورت 8787 پاسخ نمی‌دهد.'); }
    if (response.status === 401) throw new Error('توکن React با توکن Spring Boot یکسان نیست.');
    if (!response.ok) throw new Error('خطای سرور HTTP ' + response.status);
    return response.json();
  }
  async function listTabs() {
    const tabs = await chrome.tabs.query({});
    return {ok: true, tabs: tabs.filter(t => Number.isInteger(t.id)).map(info)
      .sort((a, b) => Number(b.active) - Number(a.active) || a.windowId - b.windowId)};
  }
  async function selectTab(tabId, token) {
    if (!Number.isInteger(tabId) || tabId <= 0) throw new Error('یک تب از لیست انتخاب کن.');
    const tab = await chrome.tabs.get(tabId);
    const selected = info(tab);
    await chrome.storage.session.set({gptapiyarSelectedTab: selected});
    if (!isDemo(tab.url)) {
      return {ok: true, selected, connected: false, mode: 'metadata',
        message: 'تب انتخاب و شناسایی شد؛ کنترل محتوای این سایت مجازسازی نشده است. ارسال/دریافت فقط برای demo.html فعال است.'};
    }
    await probe(token);
    let accepted;
    try {
      accepted = await chrome.tabs.sendMessage(tabId, {type: 'gptapiyar-connect', token});
    } catch {
      throw new Error('اسکریپت صفحهٔ تست آماده نیست. تب demo.html را Refresh کن و دوباره امتحان کن.');
    }
    if (!accepted?.ok) throw new Error(accepted?.message || 'فعال‌سازی تب آزمایشی ناموفق بود.');
    for (let i = 0; i < 16; i++) {
      await sleep(350);
      const status = await probe(token);
      if (status.connected && isDemo(status.pageUrl)) {
        await chrome.storage.local.set({gatewayToken: token});
        return {ok: true, selected: {...selected, connected: true},
          connected: true, mode: 'demo', message: 'اتصال آزمایشی برقرار شد.'};
      }
    }
    throw new Error('تب فعال شد، اما Spring Boot هنوز پیام heartbeat دریافت نکرده است.');
  }
  // Focus any existing Chrome tab on direct user request. This does not read its DOM.
  async function focusTab(tabId) {
    if (!Number.isInteger(tabId) || tabId <= 0) throw new Error('یک تب معتبر انتخاب کن.');
    const tab = await chrome.tabs.get(tabId);
    if (!tab || !tab.windowId) throw new Error('تب موردنظر دیگر موجود نیست.');
    await chrome.windows.update(tab.windowId, {focused: true});
    await chrome.tabs.update(tab.id, {active: true});
    return {ok: true, selected: info(tab), connected: false, mode: 'focus',
      message: 'تب انتخاب شده فعال است. در این سایت ارسال و دریافت فقط با اقدام دستی کاربر انجام می‌شود.'};
  }
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.type !== 'gptapiyar-tabs') return false;
    if (!trusted(sender)) { sendResponse({ok: false, error: 'Request origin is not trusted'}); return false; }
    const task = message.action === 'list' ? listTabs() :
      message.action === 'select' ? selectTab(message.tabId, message.token) :
      message.action === 'focus' ? focusTab(message.tabId) :
      Promise.reject(new Error('Unknown action'));
    task.then(sendResponse).catch(e => sendResponse({ok: false, error: String(e?.message || e)}));
    return true;
  });
})();
