# GptApiYar — Spring Boot + React + Browser Bridge

این پروژه یک Backend جاوا/Spring Boot و UI چت React دارد. بک‌اند روی پورت `8787` یک REST API محلی ارائه می‌کند و رابط React روی پورت `5173` باز می‌شود. برای نمایش مسیر ارتباط با مرورگر، از **Playwright Java + Chrome CDP + صفحه آزمایشی محلی** استفاده می‌کند.

> **توجه:** این نسخه هوش مصنوعی واقعی ندارد و در صفحهٔ آزمایشی پاسخ شبیه‌سازی‌شده تولید می‌کند. تبدیل خودکار سرویس ChatGPT به API، پشتیبانی‌شده/مجاز نیست. استفاده از Browser Bridge فقط روی صفحات خودتان یا صفحات دارای مجوز انجام شود. Chrome با پروفایل جداگانه راه‌اندازی می‌شود و به سشن Chrome معمولی متصل نیست.

## ۱. نصب در مسیر دقیق شما

فایل‌های `GptApiYar.zip` و `Install-GptApiYar.ps1` را دانلود کنید؛ ترجیحاً هر دو کنار هم در Downloads بمانند. در PowerShell ویندوز اجرا کنید:

```powershell
$installer = @(
  "$env:USERPROFILE\Downloads\Install-GptApiYar.ps1",
  "D:\ChromDownloads\Install-GptApiYar.ps1"
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $installer) { throw 'Installer not found in Downloads or D:\ChromDownloads' }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
```

اسکریپت فایل ZIP را از کنار خودش، Downloads، `D:\ChromDownloads` یا Desktop پیدا می‌کند، ابتدا در پوشه موقت استخراج می‌کند، محتوا را کنترل می‌کند و سپس در مسیر **`D:\ChatGPT_Projects\GptApiYar`** نصب می‌کند. فایل‌های موجود را بدون پشتیبان جایگزین نمی‌کند؛ نسخهٔ قبلی را در `D:\ChatGPT_Projects\_GptApiYar_Backups` نگه می‌دارد. در صورت بروز خطا حین کپی، برای بازیابی فایل‌های کپی‌شده تلاش می‌کند.

اگر محل ZIP متفاوت است، آدرس دلخواه را به برنامه بدهید:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\SomeFolder\Install-GptApiYar.ps1" -ZipPath "D:\SomeFolder\GptApiYar.zip"
```

## ۲. پیش‌نیازهای ویندوز

- Windows 10/11 و **Java JDK 21** (در PATH)
- **Apache Maven** (دستور `mvn.cmd`)
- **Node.js 22.12+** یا نسخهٔ پشتیبانی‌شده توسط Vite 7، به‌همراه `npm.cmd`
- **Google Chrome**
- اینترنت فقط برای دریافت وابستگی‌های Maven و npm در اولین اجرا

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\ChatGPT_Projects\GptApiYar\scripts\check-requirements.ps1"
```

## ۳. اجرای برنامه

ساده‌ترین روش (سه پنجره برای بک‌اند، React و Chrome مجزا باز می‌کند):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\ChatGPT_Projects\GptApiYar\scripts\start-all.ps1"
```

یا جداگانه از سه پنجره PowerShell در پوشهٔ پروژه:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-backend.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-chrome-debug.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-frontend.ps1
```

سپس صفحهٔ رابط کاربری را باز کنید: **http://127.0.0.1:5173**

در پنل مرورگر از پروفایل «تست محلی» استفاده کنید، روی اتصال بزنید و پیام بفرستید. اگر Chrome زودتر از Spring Boot باز شد، صفحهٔ demo را Refresh کنید.

## ۴. اجزای پروژه

```text
D:\ChatGPT_Projects\GptApiYar\
├── backend\          Spring Boot 3.x + Playwright Java + REST API
│   ├── pom.xml
│   └── src\main\...
├── frontend\         React 19 + Vite + UI چت و آپلود
│   ├── package.json
│   └── src\...
├── scripts\          شروع سرویس‌ها و بررسی پیش‌نیازها
├── Install-GptApiYar.ps1  نسخهٔ همراهِ نصب‌کننده
└── README-fa.md
```

**آدرس‌ها:**

- UI: `http://127.0.0.1:5173`
- API: `http://127.0.0.1:8787/api`
- تست صفحه: `http://127.0.0.1:8787/demo.html`
- Chrome CDP: `http://127.0.0.1:9222` (فقط localhost)

### تست REST

یک بار از پنل React به صفحهٔ demo متصل شوید. سپس از PowerShell:

```powershell
curl.exe -X POST http://127.0.0.1:8787/api/chat `
  -H "X-Gateway-Token: dev-change-this-token" `
  -F "message=سلام از API محلی"
```

به‌صورت پیش‌فرض هدر `X-Gateway-Token` با مقدار آزمایشی `dev-change-this-token` لازم است. برای کار واقعی آن را با متغیر محیطی `GATEWAY_TOKEN` تغییر بدهید و توکن جدید را داخل تنظیمات پنل React هم وارد کنید.

`/api/bridge/connect` برای اتصال به URL تب، `/api/bridge/status` برای وضعیت، و `/api/bridge/disconnect` برای قطع اتصال است. این API از URL و CSS Selector برای عناصر صفحه استفاده می‌کند. صرفِ داشتن URL یک تب برای اتصال به مرورگر کافی نیست.

## ۵. محدودیت‌ها

- React امکان انتخاب عکس و ضبط ویس را در UI دارد، اما فایل تنها در صورت وجود ورودی مناسب در صفحه مقصد به آن تحویل داده می‌شود. تحلیل تصویر یا گفتار واقعی در این نسخه وجود ندارد.
- این نسخه به تب‌های Chrome مجزا و CDP متصل می‌شود؛ **Chrome روزمره و افزونه‌هایش به‌طور خودکار در دسترس نیستند**.
- حافظه گفتگو فقط در React است و با Refresh پاک می‌شود.
- ساخت و اجرای کامل روی سیستم شما پیش از نصب قابل تأیید نبوده است.
- پورت 9222 دسترسی قدرتمندی به مرورگر می‌دهد و نباید در شبکه یا اینترنت منتشر شود؛ سرور و Chrome به `127.0.0.1` محدود شده‌اند.
- **نصب‌کننده فقط فایل‌های پروژه را استخراج می‌کند؛ Java، Maven، Node یا Chrome را نصب نمی‌کند.** وابستگی‌های Maven/npm در اولین اجرا دانلود می‌شوند.

## Maintenance: CDP diagnostic and light UI

این تغییرات رابط React را به تم روشن پیش‌فرض و بدون دکمه تم تیره تبدیل می‌کند و گفت‌وگوهای محلی را در localStorage نگه می‌دارد.
این مکالمه‌ها مستقل از مکالمات پروژه ChatGPT هستند؛ ایجاد خودکار چت ChatGPT یا تبدیل رابط وب آن به API در این نسخه پیاده نشده است.
برای آزمایش CDP، Chrome را با `scripts/start-chrome-debug.ps1` و پروفایل جداگانه اجرا کنید، سپس در React گزینه «بررسی CDP و مشاهده تب‌های مرورگر» را انتخاب کنید.
پشتیبانی از اتصال به سایت‌های ثالث فقط برای صفحات تحت کنترل یا دارای مجوز مناسب است. این برنامه برای صفحه محلی `demo.html` آمادهٔ تست است.

- `GET /api/bridge/diagnose?cdpEndpoint=http://127.0.0.1:9222` سلامت CDP را قبل از اجرای Playwright بررسی می‌کند.
- `scripts/Diagnose-GptApiYar.ps1` وضعیت React، Spring Boot، Chrome CDP و صفحه demo را گزارش می‌دهد.
- `scripts/start-backend.ps1` متغیر `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` را برای جلوگیری از دانلود Firefox/WebKit/Chromium در اجرای Maven تنظیم می‌کند.
- اگر Spring Boot از IntelliJ اجرا می‌شود، در Run Configuration همین متغیر محیطی را جداگانه اضافه کنید.
- در این نسخه اتصال Chrome از طریق CDP به Extension نیاز ندارد و Chrome روزمرهٔ شما به‌طور خودکار متصل نمی‌شود.
- تم روشن، تشخیص CDP و پایداری نمایش خطاها جایگزین وعدهٔ اتصال خودکار به ChatGPT نیست.