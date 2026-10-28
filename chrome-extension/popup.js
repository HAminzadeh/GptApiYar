// gptapiyar-popup-diagnostics-v2
// The local gateway token is shown only on explicit request; it is never printed in logs.
const $ = id => document.getElementById(id);
const demoUrl = 'http://127.0.0.1:8787/demo.html';
const apiUrl = 'http://127.0.0.1:8787/api/extension/status';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const status = (message, success = false) => {
  $('status').textContent = message;
  $('status').style.border = success ? '1px solid #a7dfc6' : '1px solid transparent';
};
function errorMessage(error) {
  return String(error && (error.message || error) || 'Unknown error');
}
function tokenValue() { return $('token').value.trim(); }

async function verifyBackend() {
  const token = tokenValue();
  if (!token) throw new Error('ابتدا توکن محلی را وارد کن. مقدار پیش فرض آزمایشی: dev-change-this-token');
  let response;
  try {
    response = await fetch(apiUrl, {
      headers: { 'X-Gateway-Token': token },
      cache: 'no-store',
      signal: AbortSignal.timeout(5000)
    });
  } catch (error) {
    throw new Error('Spring Boot روی 127.0.0.1:8787 در دسترس نیست: ' + errorMessage(error));
  }
  if (response.status === 401) {
    throw new Error('HTTP 401: توکن اشتباه است. توکن افزونه، React و GATEWAY_TOKEN سرور باید یکسان باشند.');
  }
  if (!response.ok) throw new Error('Spring Boot HTTP ' + response.status);
  const data = await response.json().catch(() => ({}));
  if (data.mode !== 'extension') throw new Error('Endpoint افزونه در Spring Boot درست پاسخ نمی دهد.');
  return data;
}
function isDemoTab(tab) {
  try {
    const u = new URL(tab.url || '');
    return u.protocol === 'http:' && u.hostname === '127.0.0.1' &&
      u.port === '8787' && u.pathname === '/demo.html';
  } catch { return false; }
}
async function refresh() {
  const tabs = (await chrome.tabs.query({url: 'http://127.0.0.1/*'})).filter(isDemoTab);
  const select = $('tab');
  const previous = select.value;
  select.replaceChildren();
  for (const tab of tabs) {
    const option = document.createElement('option');
    option.value = String(tab.id);
    option.textContent = `${tab.title || 'Local demo'} (Tab ${tab.id})`;
    select.appendChild(option);
  }
  if (tabs.some(t => String(t.id) === previous)) select.value = previous;
  status(tabs.length
    ? `${tabs.length} تب پیدا شد. این فقط شناسایی تب است؛ دکمه «اتصال» را هم بزن.`
    : 'تب demo.html پیدا نشد. صفحهٔ تست را در همین Chrome باز کن.');
}

$('toggle-token').addEventListener('click', () => {
  const visible = $('token').type === 'password';
  $('token').type = visible ? 'text' : 'password';
  $('toggle-token').textContent = visible ? 'مخفی' : 'نمایش';
  $('toggle-token').setAttribute('aria-label', visible ? 'مخفی کردن توکن' : 'نمایش توکن');
});
$('refresh').addEventListener('click', () => refresh().catch(e => status(errorMessage(e))));
$('open').addEventListener('click', async () => {
  await chrome.tabs.create({url: demoUrl});
  status('تب تست باز شد؛ پس از بارگذاری روی بازخوانی تب ها بزن.');
});
$('test-backend').addEventListener('click', async () => {
  status('در حال بررسی Spring Boot و توکن...');
  try {
    const data = await verifyBackend();
    status(data.connected
      ? 'Spring Boot و توکن معتبرند. یک تب آزمایشی هم متصل است.'
      : 'Spring Boot و توکن معتبرند. اما هنوز تب فعال نداریم؛ روی اتصال به تب کلیک کن.', true);
  } catch (error) { status(errorMessage(error)); }
});
$('connect').addEventListener('click', async () => {
  const tabId = Number($('tab').value);
  const token = tokenValue();
  if (!Number.isInteger(tabId) || tabId <= 0) {
    status('ابتدا یک تب demo.html انتخاب کن.'); return;
  }
  $('connect').disabled = true;
  try {
    status('۱/۳: بررسی توکن و سرور...');
    await verifyBackend();
    await chrome.storage.local.set({gatewayToken: token});
    status('۲/۳: فعال سازی اسکریپت داخل تب...');
    let activation;
    try {
      activation = await chrome.tabs.sendMessage(tabId, {type:'gptapiyar-connect', token});
    } catch (error) {
      throw new Error('اسکریپت افزونه داخل تب اجرا نشده. صفحه demo.html را Refresh کن و دوباره اتصال بزن. جزئیات: ' + errorMessage(error));
    }
    if (!activation?.ok) throw new Error(activation?.message || 'تب فعال نشد.');
    status('۳/۳: تأیید ارتباط واقعی با Spring Boot...');
    for (let i=0; i<15; i++) {
      await sleep(350);
      const back = await verifyBackend();
      if (back.connected && back.pageUrl?.startsWith(demoUrl)) {
        status('✅ اتصال واقعی برقرار شد. حالا در React روی بررسی اتصال افزونه بزن.', true);
        return;
      }
    }
    let debug = '';
    try {
      const detail = await chrome.tabs.sendMessage(tabId, {type:'gptapiyar-status'});
      debug = detail?.lastError ? ' خطای داخل تب: ' + detail.lastError : '';
    } catch (e) { debug = ' اسکریپت تب دیگر پاسخ نمی دهد: ' + errorMessage(e); }
    status('تب فعال شده ولی Spring Boot هنوز heartbeat دریافت نکرده است.' + debug);
  } catch (error) {
    status('اتصال ناموفق: ' + errorMessage(error));
  } finally { $('connect').disabled = false; }
});
$('disconnect').addEventListener('click', async () => {
  const tabId = Number($('tab').value);
  if (!tabId) return;
  try {
    await chrome.tabs.sendMessage(tabId, {type:'gptapiyar-disconnect'});
    status('اتصال تب قطع شد.');
  } catch (error) { status('قطع اتصال ناموفق: ' + errorMessage(error)); }
});
(async () => {
  const data = await chrome.storage.local.get('gatewayToken');
  $('token').value = data.gatewayToken || '';
  await refresh();
})().catch(e => status(errorMessage(e)));