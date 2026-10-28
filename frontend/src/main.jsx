import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Activity, ArrowDownLeft, ArrowUp, AudioLines, Bot, Check, ChevronDown, ChevronLeft, CircleHelp, Code2, Command, Copy, FileAudio2, FileImage, FileText, Globe2, Link2, Menu, MessageSquare, Mic, Moon, MoreHorizontal, Paperclip, PanelRightClose, PanelRightOpen, Plus, Power, RefreshCw, Send, Settings2, ShieldCheck, Sparkles, Square, Sun, Terminal, Trash2, Unplug, Wifi, X } from 'lucide-react';
import './style.css';

const API = 'http://127.0.0.1:8787/api';
// gptapiyar-extension-mode-v1: opt-in local demo connector
const DEMO = {
  pageUrl: 'http://127.0.0.1:8787/demo.html',
  inputSelector: '#demo-prompt',
  sendSelector: '#demo-send',
  responseSelector: '.demo-message.assistant',
  busySelector: '#demo-busy',
  fileSelector: '#demo-upload',
};
const CUSTOM = {
  pageUrl: 'https://example.com/',
  inputSelector: 'textarea',
  sendSelector: 'button[type="submit"]',
  responseSelector: '.assistant-message',
  busySelector: '',
  fileSelector: 'input[type="file"]'
};
const INITIAL = { cdpEndpoint: 'http://127.0.0.1:9222', ...DEMO };
const newThread = () => ({ id: crypto.randomUUID(), title: 'گفت‌وگوی جدید', messages: [], created: Date.now() });
function PreviewIcon({ file }) {
  return file.type.startsWith('image/') ? <FileImage size={15}/> : file.type.startsWith('audio/') ? <FileAudio2 size={15}/> : <FileText size={15}/>;
}

function App() {
  const [threads, setThreads] = useState(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('gptapiyar.threads') || 'null');
      return Array.isArray(saved) && saved.length ? saved : [newThread()];
    } catch { return [newThread()]; }
  });
  const [activeId, setActiveId] = useState(null);
  const [input, setInput] = useState('');
  const [files, setFiles] = useState([]);
  const [token, setToken] = useState('dev-change-this-token');
  // gptapiyar-react-token-visibility-v2
  const [showGatewayToken, setShowGatewayToken] = useState(false);
  const [settings, setSettings] = useState(INITIAL);
  const [transport, setTransport] = useState('extension');
  // gptapiyar-tabs-v1: current Chrome tab discovery and explicit user selection.
  const [chromeTabs, setChromeTabs] = useState([]);
  const [chromeTabId, setChromeTabId] = useState('');
  const [chromeTabsReady, setChromeTabsReady] = useState(false);
  const [chromeTabsBusy, setChromeTabsBusy] = useState(false);
  const [chromeTabsNote, setChromeTabsNote] = useState('');
  const chromeTabCallbacks = useRef(new Map());

  // gptapiyar-smart-onboarding-v1
  const [smartUrl, setSmartUrl] = useState('http://127.0.0.1:8787/demo.html');
  const [extensionInstalled, setExtensionInstalled] = useState(false);
  const [smartBusy, setSmartBusy] = useState(false);
  const [smartNotice, setSmartNotice] = useState('');
  const [showSmartGuide, setShowSmartGuide] = useState(false);
  const smartPendingRef = useRef(new Map());
  const smartLastSeenRef = useRef(0);
  const [preset, setPreset] = useState('demo');
  const [advanced, setAdvanced] = useState(false);
  const [isConnected, setConnected] = useState(false);
  const [status, setStatus] = useState('آماده برای اتصال');
  const [tabTitle, setTabTitle] = useState('');
  const [connecting, setConnecting] = useState(false);
  const [cdpReport, setCdpReport] = useState(null);
  const [sending, setSending] = useState(false);
  const [showInspector, setShowInspector] = useState(true);
  const [showSidebar, setShowSidebar] = useState(true);
  // Light theme only; dark mode deliberately disabled.
  const [recording, setRecording] = useState(false);
  const [notice, setNotice] = useState('');
  const [logs, setLogs] = useState([{ at: 'شروع برنامه', text: 'کنسول آماده است', kind: 'neutral' }]);
  const scrollRef = useRef(null);
  const fileRef = useRef(null);
  const recorderRef = useRef(null);
  const streamRef = useRef(null);
  const active = threads.find(t => t.id === activeId) || threads[0];

  const log = (text, kind='neutral') => {
    setLogs(prev => [{ at: new Date().toLocaleTimeString('fa-IR', {hour:'2-digit',minute:'2-digit',second:'2-digit'}), text, kind }, ...prev].slice(0, 12));
  };
  const request = async (path, options={}) => {
    const { timeoutMs = 10000, ...fetchOptions } = options;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const result = await fetch(API + path, {
        ...fetchOptions,
        signal: controller.signal,
        headers: { 'X-Gateway-Token': token, ...(fetchOptions.body instanceof FormData ? {} : { 'Content-Type':'application/json' }), ...fetchOptions.headers }
      });
      const data = await result.json().catch(() => ({}));
      if(!result.ok) throw new Error(data.error || `خطای سرور: ${result.status}`);
      return data;
    } catch (e) {
      if (e.name === 'AbortError') throw new Error('مهلت درخواست تمام شد؛ وضعیت Chrome CDP و Spring Boot را بررسی کن.');
      throw e;
    } finally { clearTimeout(timer); }
  };
  const checkStatus = async () => {
    try {
      const s = await request(transport === 'extension' ? '/extension/status' : '/bridge/status');
      setConnected(!!s.connected);
      setTabTitle(s.title || '');
      setStatus(s.connected ? 'مرورگر متصل است' : 'اتصال برقرار نیست');
    } catch {
      setConnected(false);setStatus('بررسی اتصال ناموفق؛ توکن React و سرور را کنترل کن');
    }
  };
  useEffect(() => { checkStatus(); }, [token, transport]);
  // Detect the extension in THIS Chrome profile; no extension ID or CDP required.
  useEffect(() => {
    const receive = event => {
      if (event.source !== window || event.origin !== window.location.origin) return;
      const data = event.data;
      if (data?.source !== 'gptapiyar-extension-ui') return;
      smartLastSeenRef.current = Date.now();
      setExtensionInstalled(true);
      if (data.type === 'result' && data.requestId) {
        const done = smartPendingRef.current.get(data.requestId);
        if (done) {smartPendingRef.current.delete(data.requestId); done(data.result);}
      }
    };
    window.addEventListener('message', receive);
    const ping = () => {
      if (smartLastSeenRef.current && Date.now() - smartLastSeenRef.current > 6500) setExtensionInstalled(false);
      window.postMessage({source: 'gptapiyar-web', type: 'request', action: 'ping', requestId: crypto.randomUUID()}, window.location.origin);
    };
    ping();
    const timer = setInterval(ping, 2000);
    return () => {window.removeEventListener('message', receive); clearInterval(timer);};
  }, []);
  useEffect(() => {
    try { localStorage.setItem('gptapiyar.threads', JSON.stringify(threads)); } catch {}
  }, [threads]);
  useEffect(() => { const timer = setInterval(checkStatus, transport === 'extension' ? 3000 : 12000);return () => clearInterval(timer); }, [token, transport]);
  useEffect(() => { scrollRef.current?.scrollIntoView({ behavior:'smooth' }); }, [threads, activeId, sending]);

  useEffect(() => {
    const onMessage = event => {
      if (event.source !== window || event.origin !== window.location.origin) return;
      const data = event.data;
      if (data?.source !== 'gptapiyar-tabs-extension') return;
      if (data.type === 'ready') setChromeTabsReady(true);
      if (data.type === 'result' && data.requestId) {
        const cb = chromeTabCallbacks.current.get(data.requestId);
        if (cb) { chromeTabCallbacks.current.delete(data.requestId); cb(data.result); }
      }
    };
    window.addEventListener('message', onMessage);
    window.postMessage({source: 'gptapiyar-tabs-web', type: 'ping'}, window.location.origin);
    return () => {window.removeEventListener('message', onMessage); chromeTabCallbacks.current.clear();};
  }, []);

  const chromeTabRequest = (action, params = {}) => new Promise((resolve, reject) => {
    const requestId = crypto.randomUUID();
    const timer = setTimeout(() => {
      chromeTabCallbacks.current.delete(requestId);
      reject(new Error('پاسخی از افزونه دریافت نشد؛ افزونه و صفحه React را Reload کن.'));
    }, 14000);
    chromeTabCallbacks.current.set(requestId, result => {clearTimeout(timer); resolve(result);});
    window.postMessage({source: 'gptapiyar-tabs-web', type: 'request', requestId, action, ...params}, window.location.origin);
  });
  const openSelectedChromeTab = async () => {
    if (!chromeTabId) {setChromeTabsNote('ابتدا یک تب را انتخاب کن.'); return;}
    setChromeTabsBusy(true);
    try {
      // Clipboard access requires this direct user click; do it before tab focus.
      if (input.trim()) {
        if (!navigator.clipboard?.writeText) throw new Error('مرورگر اجازهٔ کپی در کلیپ‌بورد را نداد.');
        await navigator.clipboard.writeText(input.trim());
      }
      const result = await chromeTabRequest('focus', {tabId: Number(chromeTabId)});
      if (!result?.ok) throw new Error(result?.error || 'فعال‌کردن تب انجام نشد.');
      setChromeTabsNote(input.trim()
        ? 'متن در کلیپ‌بورد کپی شد. در تب بازشده خودت پیام را Paste و ارسال کن؛ سپس پاسخ را Copy کن.'
        : 'تب در Chrome فعال شد. برای ارسال، ابتدا یک پیام در فرم React بنویس.');
    } catch (e) {setChromeTabsNote(e.message);}
    finally {setChromeTabsBusy(false);}
  };
  const insertManualResponse = async () => {
    try {
      if (!navigator.clipboard?.readText) throw new Error('خواندن کلیپ‌بورد از این مرورگر ممکن نیست.');
      const copied = (await navigator.clipboard.readText()).trim();
      if (!copied) throw new Error('متنی در کلیپ‌بورد وجود ندارد.');
      updateActive(t => ({...t,messages:[...t.messages,{id:crypto.randomUUID(),role:'assistant',text:'[پاسخ منتقل‌شده به‌صورت دستی]\n\n'+copied}]}));
      setChromeTabsNote('متن پاسخ دستی وارد گفتگو شد. این پاسخ از سایت به‌طور خودکار استخراج نشده است.');
    } catch (e) {setChromeTabsNote(e.message);}
  };
  const refreshChromeTabs = async () => {
    setChromeTabsBusy(true);
    try {
      const result = await chromeTabRequest('list');
      if (!result?.ok) throw new Error(result?.error || 'دریافت تب‌ها ناموفق بود.');
      setChromeTabs(result.tabs || []);
      setChromeTabId(current => result.tabs?.some(t => String(t.id) === current)
        ? current : String(result.tabs?.find(t => t.kind === 'demo')?.id || result.tabs?.[0]?.id || ''));
      setChromeTabsNote(`${(result.tabs || []).length} تب شناسایی شد. انتخاب تب به معنی اجازه خواندن پیام‌های آن نیست.`);
    } catch(e) {setChromeTabsNote(e.message);}
    finally {setChromeTabsBusy(false);}
  };
  useEffect(() => {
    if (chromeTabsReady && transport === 'extension') refreshChromeTabs();
  }, [chromeTabsReady, transport]);
  const selectChromeTab = async () => {
    if (!chromeTabId) {setChromeTabsNote('ابتدا تب موردنظر را انتخاب کن.'); return;}
    setChromeTabsBusy(true);
    try {
      const result = await chromeTabRequest('select', {tabId: Number(chromeTabId), token});
      if (!result?.ok) throw new Error(result?.error || 'انتخاب تب ناموفق بود.');
      setChromeTabsNote(result.message || 'تب انتخاب شد.');
      if (result.connected) {
        setConnected(true);
        setTabTitle(result.selected?.title || 'Local demo');
        setStatus('تب آزمایشی متصل است');
        log('Chrome: demo tab connected', 'success');
      } else {
        setConnected(false);
        setStatus('تب انتخاب شد؛ اتصال چت فعال نیست');
        log('Chrome tab selected (metadata only)', 'neutral');
      }
    } catch(e) { setChromeTabsNote(e.message); log(e.message, 'error'); }
    finally {setChromeTabsBusy(false);}
  };

  const choosePreset = value => {
    setPreset(value);
    setSettings(current => ({...current, ...(value === 'demo' ? DEMO : CUSTOM)}));
    setAdvanced(value === 'custom');
  };
  const diagnose = async () => {
    setNotice(''); setCdpReport(null);
    try {
      const report = await request('/bridge/diagnose?cdpEndpoint=' + encodeURIComponent(settings.cdpEndpoint), {timeoutMs: 6000});
      setCdpReport(report);
      setNotice(report.reachable ? `CDP فعال است؛ ${report.tabs.length} تب در دسترس است.` : report.message);
      log(report.reachable ? 'CDP در دسترس است' : report.message, report.reachable ? 'success' : 'error');
    } catch(e) {setNotice(e.message); log(e.message, 'error');}
  };
  const checkExtension = async () => {
    setNotice('');
    try {
      const result = await request('/extension/status');
      setConnected(!!result.connected);
      setTabTitle(result.title || '');
      setStatus(result.connected ? 'Chrome اصلی متصل است' : 'افزونه به صفحه تست متصل نیست');
      setNotice(result.connected ? `افزونه به تب ${result.title || 'demo.html'} متصل است.` : 'افزونه را در Chrome اصلی از chrome://extensions نصب کن؛ سپس از پنجره افزونه تب demo.html را انتخاب و فعال کن.');
    } catch (e) { setNotice(e.message); }
  };
  const smartConnect = async () => {
    const url = smartUrl.trim();
    if (url !== 'http://127.0.0.1:8787/demo.html') {
      setSmartNotice('این نسخه فقط به صفحهٔ تست محلی متصل می‌شود؛ آدرس ChatGPT یا سایت‌های دیگر پشتیبانی نمی‌شود.');
      return;
    }
    if (!token.trim()) {setSmartNotice('ابتدا توکن محلی Spring Boot را وارد کن.'); return;}
    if (!extensionInstalled) {
      setShowSmartGuide(true);
      setSmartNotice('افزونه در این Chrome شناسایی نشد. ZIP دانلود می‌شود؛ آن را Extract کن و با Load unpacked نصب کن. سپس صفحه React را Refresh کن.');
      const anchor = document.createElement('a');
      anchor.href = '/GptApiYar-Chrome-Extension.zip';
      anchor.download = 'GptApiYar-Chrome-Extension.zip';
      document.body.appendChild(anchor); anchor.click(); anchor.remove();
      return;
    }
    setSmartBusy(true);setSmartNotice('در حال بررسی سرور، آماده‌سازی تب و تأیید اتصال...');setNotice('');
    try {
      const requestId = crypto.randomUUID();
      const result = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {smartPendingRef.current.delete(requestId); reject(new Error('افزونه در مهلت مشخص پاسخ نداد. افزونه و صفحه React را Reload کن.'));}, 22000);
        smartPendingRef.current.set(requestId, answer => {clearTimeout(timer);resolve(answer);});
        window.postMessage({source: 'gptapiyar-web', type: 'request', action: 'connect', requestId, token, url}, window.location.origin);
      });
      if (!result?.ok) throw new Error(result?.error || 'اتصال تأیید نشد.');
      setConnected(true);setTabTitle(result.title || 'GptApiYar Demo');
      setStatus('Chrome فعلی متصل است');
      setSmartNotice('✅ اتصال واقعی برقرار شد. اکنون از فرم چت یک پیام آزمایشی بفرست.');
      log('Chrome اصلی و تب تست متصل شدند', 'success');
    } catch (error) {setConnected(false);setStatus('اتصال ناموفق');setSmartNotice(error.message);log('اتصال افزونه: '+error.message,'error');}
    finally {setSmartBusy(false);}
  };
  const connect = async () => {
    setConnecting(true);setNotice('');
    try {
      const result = await request('/bridge/connect', { method:'POST', body: JSON.stringify(settings), timeoutMs: 18000 });
      setConnected(true);setTabTitle(result.title);setStatus('مرورگر متصل است');log('اتصال موفق: ' + result.title, 'success');
    } catch (e) {setConnected(false);setStatus('اتصال ناموفق');setNotice(e.message);log('خطای اتصال: ' + e.message, 'error');}
    finally {setConnecting(false);}
  };
  const disconnect = async () => {
    try {await request('/bridge/disconnect', { method:'POST', body:'{}' });setConnected(false);setStatus('اتصال قطع شد');log('اتصال به مرورگر قطع شد');}
    catch (e) {setNotice(e.message);}
  };
  const updateActive = fn => setThreads(current => current.map(t => t.id === active.id ? fn(t) : t));
  const send = async (manualText=null) => {
    if(sending) return;
    if(transport === 'extension' && files.length) { setNotice('حالت افزونه در این نسخه فقط متن را در صفحه demo.html تست می‌کند؛ برای فایل از حالت CDP استفاده کن.'); return; }
    const text = (typeof manualText === 'string' ? manualText : input).trim();
    if(!text && files.length === 0) return;
    if(!isConnected) {setNotice('ابتدا در بخش Browser Connection به تب مرورگر متصل شو.');return;}
    const attachments = files.map(f => f.name);
    updateActive(t => ({...t, title:t.messages.length === 0 ? (text || attachments.join('، ')).slice(0, 30) : t.title, messages:[...t.messages,{ id:crypto.randomUUID(), role:'user', text, attachments }] }));
    setInput('');setFiles([]);setSending(true);setNotice('');log('POST /api/chat', 'neutral');
    const payload = new FormData();payload.append('message', text);for(const f of files) payload.append('files', f, f.name);
    try {
      const result = await request(transport === 'extension' ? '/extension/chat' : '/chat', { method:'POST', body:payload, timeoutMs: 105000 });
      updateActive(t => ({...t,messages:[...t.messages,{id:result.id,role:'assistant',text:result.message}]}));
      log('پاسخ مرورگر دریافت شد', 'success');
    } catch(e) {
      updateActive(t => ({...t,messages:[...t.messages,{id:crypto.randomUUID(),role:'error',text:e.message}]}));
      log('درخواست ناموفق: ' + e.message, 'error');
    } finally {setSending(false);}
  };
  const createChat = () => {
    const chat = newThread();setThreads(current => [chat, ...current]);setActiveId(chat.id);setInput('');setFiles([]);
  };
  const deleteChat = id => {
    const filtered = threads.filter(t=>t.id!==id);
    if(filtered.length === 0) {const c=newThread();setThreads([c]);setActiveId(c.id);}
    else {setThreads(filtered);if(active.id===id)setActiveId(filtered[0].id);}
  };
  const startOrStopRecording = async () => {
    if (recording) {recorderRef.current?.stop();setRecording(false);return;}
    try {
      const stream=await navigator.mediaDevices.getUserMedia({audio:true});
      const parts=[];const recorder=new MediaRecorder(stream);
      recorderRef.current=recorder;streamRef.current=stream;
      recorder.ondataavailable=e=>{if(e.data.size)parts.push(e.data);};
      recorder.onstop=()=>{
        const mime=recorder.mimeType || 'audio/webm';const ext=mime.includes('mp4')?'mp4':'webm';
        const file=new File(parts, `voice-${Date.now()}.${ext}`, {type:mime});
        setFiles(existing=>[...existing,file]);stream.getTracks().forEach(track=>track.stop());
        log('ویس به پیوست‌ها اضافه شد');
      };
      recorder.start();setRecording(true);
    } catch(e) {setNotice('دسترسی میکروفون امکان‌پذیر نیست: '+e.message);}
  };
  const onFiles = e => {const chosen=[...(e.target.files||[])];setFiles(current=>[...current,...chosen]);e.target.value='';};
  const handleKey = e => {if(e.key==='Enter' && !e.shiftKey){e.preventDefault();send();}};
  const copyApi = () => {navigator.clipboard?.writeText('http://127.0.0.1:8787/api/chat');setNotice('آدرس API کپی شد.');};

  return <div className="app light" dir="rtl">
    {showSidebar && <aside className="sidebar">
      <div className="brand"><div className="brand-symbol"><Command size={19}/></div><div><b>GptApiYar</b><span>Browser Bridge</span></div><button className="icon-button push-left" title="بستن سایدبار" onClick={()=>setShowSidebar(false)}><PanelRightClose size={18}/></button></div>
      <button className="new-chat" onClick={createChat}><Plus size={18}/> گفت‌وگوی جدید <span className="short-key">Ctrl N</span></button>
      <div className="sidebar-label">گفت‌وگوهای اخیر</div>
      <div className="chat-list">{threads.map(t=><div key={t.id} className={'thread '+(active.id===t.id?'selected':'')}>
        <button onClick={()=>setActiveId(t.id)}><MessageSquare size={15}/><span>{t.title}</span></button>
        <button className="delete-chat" title="حذف مکالمه" onClick={()=>deleteChat(t.id)}><X size={14}/></button>
      </div>)}</div>
      <div className="sidebar-footer"><div className="mini-status"><span className={'pulse '+(isConnected?'online':'')}></span><span>{status}</span></div><div className="sidebar-meta"><ShieldCheck size={16}/> فقط روی دستگاه شما</div></div>
    </aside>}
    <main className="main">
      <header className="topbar">
        <div className="topbar-start">{!showSidebar&&<button className="icon-button" onClick={()=>setShowSidebar(true)}><Menu size={20}/></button>}<div className="top-logo"><Sparkles size={17}/></div><span className="top-name">چت آزمایشی</span><span className="top-divider"></span><span className="top-sub">Local Browser Gateway</span></div>
        <div className="top-actions"><div className={'connection-pill '+(isConnected?'active':'')}><span className="pulse online"></span>{isConnected?'Connected':'Disconnected'}</div><button className="icon-button" title="تنظیمات اتصال" onClick={()=>setShowInspector(v=>!v)}>{showInspector?<PanelRightClose size={20}/>:<PanelRightOpen size={20}/>}</button></div>
      </header>
      <div className="conversation" id="conversation">
        {active.messages.length===0 ? <div className="empty-state">
          <div className="hero-mark"><Sparkles size={35}/></div>
          <div className="eyebrow">SAKHTYAR / BROWSER BRIDGE</div>
          <h1>امروز چی می‌خوای امتحان کنیم؟</h1>
          <p>از این صفحه به گیت‌وی محلی درخواست بفرست. اگر به یک تب مرورگر متصل باشی، ارسال و دریافت از همان صفحه انجام می‌شود.</p>
          <div className="suggestion-grid">
            {[['تست اتصال','یک پیام آزمایشی برای بررسی ارتباط بفرست','سلام! این یک تست ارتباطی است.'],['ارسال فایل','یک تصویر یا سند به پیام اضافه کن','این فایل را بررسی کن.'],['آزمایش پاسخ','مطمئن شو پاسخ از صفحه خوانده می‌شود','لطفاً یک پاسخ کوتاه آزمایشی بده.'],['وضعیت گیت‌وی','تنظیمات و اتصال مرورگر را بررسی کن','وضعیت ارتباط برقرار است؟']].map(([title,desc,value],i)=><button className="suggestion" key={title} onClick={()=>setInput(value)}><span className="suggest-icon">{[<Terminal size={17}/>,<FileImage size={17}/>,<MessageSquare size={17}/>,<Activity size={17}/>][i]}</span><b>{title}</b><small>{desc}</small><ArrowUp size={14} className="suggest-arrow"/></button>)}
          </div>
        </div> : <div className="messages">{active.messages.map(m=><div key={m.id} className={'message '+m.role}>
          <div className="avatar">{m.role==='user'?<span>ش</span>:m.role==='error'?<X size={17}/>:<Sparkles size={17}/>}</div>
          <div className="message-content"><div className="message-author">{m.role==='user'?'شما':m.role==='assistant'?'پاسخ مرورگر':'خطای سرویس'}</div><div className="message-text" dir="auto">{m.text||'(بدون متن)'}</div>{m.attachments?.length>0&&<div className="message-attachments">{m.attachments.map((n,i)=><span key={i}><Paperclip size={13}/>{n}</span>)}</div>}</div>
        </div>)}{sending&&<div className="message assistant"><div className="avatar"><Sparkles size={17}/></div><div className="message-content"><div className="message-author">در انتظار مرورگر</div><div className="loading-dots"><i></i><i></i><i></i></div></div></div>}<div ref={scrollRef}/></div>}
      </div>
      <div className="composer-shell">
        {notice&&<div className="notice"><CircleHelp size={16}/><span>{notice}</span><button onClick={()=>setNotice('')}><X size={15}/></button></div>}
        <div className="composer">
          {!!files.length&&<div className="pending-files">{files.map((f,i)=><span key={i}><PreviewIcon file={f}/><small>{f.name}</small><button title="حذف پیوست" onClick={()=>setFiles(old=>old.filter((_,index)=>index!==i))}><X size={13}/></button></span>)}</div>}
          <textarea value={input} onChange={e=>setInput(e.target.value)} onKeyDown={handleKey} placeholder="پیامی برای تست گیت‌وی بنویس..." rows={2} />
          <div className="composer-toolbar"><div className="composer-tools"><input ref={fileRef} type="file" multiple accept="image/*,audio/*,.pdf,.txt" hidden onChange={onFiles}/><button className="tool-btn" title="افزودن تصویر یا فایل" onClick={()=>fileRef.current?.click()}><Paperclip size={18}/></button><button className={'tool-btn '+(recording?'recording':'')} title={recording?'توقف ضبط':'ضبط صدا'} onClick={startOrStopRecording}>{recording?<Square size={16} fill="currentColor"/>:<Mic size={19}/>}</button><span className="tool-separator"></span><span className="tool-hint">{recording?'در حال ضبط صدا...':'Enter برای ارسال'}</span></div><button disabled={sending||(!input.trim()&&!files.length)} className="send-btn" title="ارسال" onClick={()=>send()}>{sending?<RefreshCw className="spin" size={19}/>:<ArrowUp size={20}/>}</button></div>
        </div>
        <div className="composer-foot">این رابط فقط یک کلاینت آزمایشی است؛ خروجی به صفحه و تنظیمات اتصال شما بستگی دارد.</div>
      </div>
    </main>
    {showInspector&&<aside className="inspector">
      <div className="inspector-header"><div><span className="panel-eyebrow">CONTROL CENTER</span><h2>اتصال مرورگر</h2></div><button className="icon-button" onClick={()=>setShowInspector(false)}><X size={18}/></button></div>
      <div className="inspector-scroll">
        <div className={'status-card '+(isConnected?'success':'')}><div className="status-icon"><Globe2 size={20}/></div><div><b>{isConnected?'اتصال برقرار است':'در انتظار اتصال'}</b><small dir="auto">{isConnected?(tabTitle||settings.pageUrl):(transport === 'extension' ? 'افزونه را بررسی یا نصب کن' : 'Chrome را در حالت CDP اجرا کنید')}</small></div><span className={'status-led '+(isConnected?'on':'')}></span></div>
        <div className="transport-choices">
          <button className={transport==='extension'?'selected':''} onClick={()=>{setTransport('extension');setConnected(false);setNotice('');}}>Chrome فعلی (افزونه)</button>
          <button className={transport==='cdp'?'selected':''} onClick={()=>{setTransport('cdp');setConnected(false);setNotice('');}}>CDP آزمایشی</button>
        </div>
        {transport === 'extension' && <div className="extension-panel smart-setup">
          <div className="all-tabs-panel">
            <div className="all-tabs-header"><b>تب‌های باز Chrome اصلی</b><button type="button" onClick={refreshChromeTabs} disabled={chromeTabsBusy}>بازخوانی تب‌ها</button></div>
            {!chromeTabsReady ? <p className="all-tabs-help">افزونه هنوز در این صفحه شناسایی نشده است. افزونه را Reload کن و React را Refresh کن.</p> : <>
              <label htmlFor="gpy-chrome-tabs">انتخاب تب مرورگر</label>
              <select id="gpy-chrome-tabs" value={chromeTabId} onChange={e=>setChromeTabId(e.target.value)}>
                <option value="">انتخاب کن...</option>
                {chromeTabs.map(t=><option key={t.id} value={String(t.id)}>{t.kind==='demo'?'✅ ':'◦ '}{t.title} — {t.url}</option>)}
              </select>
              <button type="button" className="primary-action" disabled={chromeTabsBusy || !chromeTabId} onClick={selectChromeTab}>{chromeTabsBusy ? 'در حال بررسی...' : 'انتخاب و اتصال به تب'}</button>
              <button type="button" className="all-tabs-secondary" disabled={chromeTabsBusy || !chromeTabId} onClick={openSelectedChromeTab}>کپی متن پیام و رفتن به تب</button>
              <button type="button" className="all-tabs-secondary" disabled={chromeTabsBusy} onClick={insertManualResponse}>ثبت پاسخ کپی‌شده در گفتگو</button>
              <p className="all-tabs-help">تمام تب‌های Chrome نمایش داده می‌شوند؛ محدودیت دامنه برای فهرست وجود ندارد. ارسال/دریافت خودکار فقط در صفحهٔ آزمایشی خودمان فعال است. در سایت‌های دیگر می‌توان متن را کپی و تب را باز کرد و پاسخ کپی‌شده را دستی وارد نمود. محتوای تب‌ها بدون اجازه خوانده نمی‌شود.</p>
            </>}
            {chromeTabsNote && <p className="all-tabs-note" role="status">{chromeTabsNote}</p>}
          </div>

          <b>اتصال آسان به Chrome فعلی</b>
          <p>آدرس را بررسی کن و روی دکمه بزن. افزونهٔ نصب‌شده بررسی و تب مجاز در همین Chrome آماده می‌شود.</p>
          <div className="smart-setup-status">
            <span className={extensionInstalled ? 'smart-setup-ok' : 'smart-setup-warn'}>{extensionInstalled ? '✓ افزونه در همین Chrome شناسایی شد' : '○ افزونه در این صفحه شناسایی نشده'}</span>
            <span className={isConnected ? 'smart-setup-ok' : 'smart-setup-muted'}>{isConnected ? '✓ ارتباط با Spring Boot برقرار است' : '○ منتظر اتصال تب آزمایشی'}</span>
          </div>
          <label className="smart-setup-label" htmlFor="gptapiyar-smart-url">آدرس تب موردنظر</label>
          <input id="gptapiyar-smart-url" className="simple-input smart-url-input" dir="ltr" spellCheck="false" value={smartUrl} onChange={e=>setSmartUrl(e.target.value)}/>
          <small>در نسخهٔ فعلی فقط http://127.0.0.1:8787/demo.html پشتیبانی می‌شود.</small>
          <button className="primary-action smart-install-connect" onClick={smartConnect} disabled={smartBusy}>{smartBusy ? 'در حال بررسی و اتصال...' : 'نصب افزونه و اتصال به URL'}</button>
          {smartNotice && <p className="smart-setup-message" role="status">{smartNotice}</p>}
          <button className="smart-setup-help" onClick={()=>setShowSmartGuide(v=>!v)}>{showSmartGuide ? 'بستن راهنمای نصب' : 'افزونه نصب نیست؟ راهنمای نصب اولیه'}</button>
          {showSmartGuide && <div className="smart-setup-guide">
            <p>Chrome نصب خودکار و بی‌اجازهٔ افزونه را مجاز نمی‌داند. نصب اولیه یک بار باید با تأیید خودت انجام شود:</p>
            <ol>
              <li><a href="/GptApiYar-Chrome-Extension.zip" download>دانلود افزونه ZIP</a> و Extract All</li>
              <li>بازکردن <code>chrome://extensions</code> در Chrome فعلی</li>
              <li>فعال‌کردن Developer mode و انتخاب Load unpacked</li>
              <li>انتخاب پوشهٔ حاوی <code>manifest.json</code></li>
              <li>بارگذاری مجدد صفحهٔ React و کلیک دوباره روی دکمهٔ اتصال</li>
            </ol>
          </div>}
          <button className="cdp-diagnose-btn" onClick={checkExtension}>بررسی دستی وضعیت اتصال</button>
          <small>توکن موجود در بخش «توکن محلی برنامه» به افزونه منتقل می‌شود؛ نیازی به وارد کردن مجدد آن در Popup نیست.</small>
        </div>}
        {transport === 'cdp' && <>
        <div className="section-header"><span>پروفایل صفحه</span><span className="muted">01</span></div>
        <div className="profile-choices"><button className={preset==='demo'?'chosen':''} onClick={()=>choosePreset('demo')}><span>🧪</span> تست محلی</button><button className={preset==='custom'?'chosen':''} onClick={()=>choosePreset('custom')}><span>🌐</span> سفارشی</button></div>
        <div className="form-field"><label>آدرس CDP</label><div className="input-wrap" dir="ltr"><Link2 size={15}/><input value={settings.cdpEndpoint} onChange={e=>setSettings({...settings,cdpEndpoint:e.target.value})} spellCheck="false"/></div><small>Chrome باید با پورت دیباگ اجرا شده باشد.</small></div>
        <div className="form-field"><label>آدرس تب مرورگر</label><div className="input-wrap" dir="ltr"><Globe2 size={15}/><input value={settings.pageUrl} onChange={e=>setSettings({...settings,pageUrl:e.target.value})} spellCheck="false"/></div><small>آدرس دقیق همان تبی که باز کرده‌اید.</small></div>
        <button className="advanced-toggle" onClick={()=>setAdvanced(!advanced)}><Settings2 size={16}/> تنظیمات عناصر صفحه <ChevronDown className={advanced?'flip':''} size={16}/></button>
        {advanced&&<div className="selector-fields">{[['inputSelector','ورودی پیام'],['sendSelector','دکمه ارسال'],['responseSelector','المان پاسخ'],['busySelector','نشانگر انتظار (اختیاری)'],['fileSelector','ورودی فایل (اختیاری)']].map(([name,label])=><div className="form-field" key={name}><label>{label}</label><input className="simple-input" dir="ltr" spellCheck="false" value={settings[name]} onChange={e=>setSettings({...settings,[name]:e.target.value})}/></div>)}</div>}
        <button className="cdp-diagnose-btn" onClick={diagnose}>بررسی CDP و مشاهده تب‌های مرورگر</button>
        {cdpReport && <div className="cdp-report">
          <b>{cdpReport.reachable ? `متصل: ${cdpReport.browser}` : 'CDP در دسترس نیست'}</b>
          {cdpReport.tabs?.slice(0, 20).map((tab, i) => <button key={`${tab.url}-${i}`} title={tab.url}
            onClick={() => {setSettings(current => ({...current, pageUrl: tab.url})); setPreset('custom'); setAdvanced(true);}}>
            {tab.title || tab.url}
          </button>)}
        </div>}
        <div className="connection-actions"><button className="primary-action" disabled={connecting} onClick={connect}>{connecting?<RefreshCw className="spin" size={17}/>:<Power size={17}/>} {connecting?'در حال اتصال...':'اتصال به مرورگر'}</button><button className="secondary-action" title="قطع ارتباط" disabled={!isConnected} onClick={disconnect}><Unplug size={18}/></button></div>
        </>}
        <div className="section-header api-title"><span>REST API</span><span className="muted">02</span></div>
        <div className="api-box"><div className="api-badge"><span className="method">POST</span><span>localhost:8787</span></div><div className="api-endpoint" dir="ltr">/api/chat <button title="کپی URL" onClick={copyApi}><Copy size={14}/></button></div></div>
        <div className="form-field"><label>توکن محلی برنامه</label><div className="gpt-token-row"><input className="simple-input" dir="ltr" type={showGatewayToken ? "text" : "password"} value={token} onChange={e=>setToken(e.target.value)}/><button type="button" className="gpt-token-toggle" onClick={()=>setShowGatewayToken(v=>!v)}>{showGatewayToken ? "مخفی" : "نمایش"}</button></div><small>توکن API مرورگر نیست؛ فقط برای حفاظت از گیت‌وی محلی است.</small></div>
        <div className="section-header"><span>گزارش درخواست‌ها</span><span className="muted">03</span></div>
        <div className="log-box">{logs.slice(0,5).map((l,i)=><div className="log-entry" key={i}><span className={'log-dot '+l.kind}></span><span>{l.text}</span><small>{l.at}</small></div>)}</div>
        <div className="security-note"><ShieldCheck size={17}/><p>REST API و CDP را فقط روی Loopback اجرا کن. این نمونه برای توسعه و تست شخصی است.</p></div>
      </div>
      <div className="inspector-bottom"><span><span className="dot-green"></span>Spring Boot :8787</span><span>React / Vite</span></div>
    </aside>}
  </div>;
}

createRoot(document.getElementById('root')).render(<App/>);
