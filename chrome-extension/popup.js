const $ = id => document.getElementById(id);
const demoUrl = 'http://127.0.0.1:8787/demo.html';
const status = message => { $('status').textContent = message; };

async function refresh() {
  const tabs = (await chrome.tabs.query({url: 'http://127.0.0.1/demo.html*'}))
    .filter(t => t.url?.startsWith(demoUrl));
  const select = $('tab');
  select.replaceChildren();
  for (const tab of tabs) {
    const option = document.createElement('option');
    option.value = String(tab.id);
    option.textContent = `${tab.title || 'Local demo'} (Tab ${tab.id})`;
    select.appendChild(option);
  }
  status(tabs.length ? `${tabs.length} local demo tab(s) found` : 'No demo tab. Open it with the button above, then refresh.');
}

$('refresh').addEventListener('click', () => refresh().catch(e => status(e.message)));
$('open').addEventListener('click', async () => {
  await chrome.tabs.create({url: demoUrl});
  status('Demo opened in this Chrome. Wait for loading, then click Refresh.');
});
$('connect').addEventListener('click', async () => {
  const tabId = Number($('tab').value);
  const token = $('token').value.trim();
  if (!Number.isInteger(tabId) || tabId <= 0 || !token) {
    status('Select a demo tab and enter the local gateway token.'); return;
  }
  await chrome.storage.local.set({gatewayToken: token});
  try {
    const result = await chrome.tabs.sendMessage(tabId, {type:'gptapiyar-connect', token});
    status(result?.ok ? 'Connected. Go to React and choose Chrome Extension mode.' : (result?.message || 'Could not activate tab'));
  } catch (error) {
    status('The content script is not ready. Reload the demo tab and try again. ' + error.message);
  }
});
$('disconnect').addEventListener('click', async () => {
  const tabId = Number($('tab').value);
  if (tabId) {
    try { await chrome.tabs.sendMessage(tabId, {type:'gptapiyar-disconnect'}); status('Tab disconnected'); }
    catch (error) { status('Could not reach tab: ' + error.message); }
  }
});
(async () => {
  const data = await chrome.storage.local.get('gatewayToken');
  $('token').value = data.gatewayToken || '';
  await refresh();
})().catch(e => status(e.message));
