# Auth & API Porting Map — Flutter → Swift/SwiftUI

> Source of truth for the iOS rewrite. Generated from the Flutter codebase at
> `/Users/clapecho233/Files/Work/Bugaoshan` (branch `main`, commit `864ea71`-era, 2026-09).
> Every URL, header, key name, regex and constant below is quoted verbatim from Dart source.
> Cross-check doc: `docs/architecture/authentication.md` in the Flutter repo (authoritative narrative;
> this file is the endpoint/constant-level extract).

---

## Table of Contents

1. [Global Constants](#1-global-constants)
2. [Three-Layer Architecture Summary](#2-three-layer-architecture-summary)
3. [CookieClient (transport layer)](#3-cookieclient-transport-layer)
4. [ScuAuth — Root Flow (L3)](#4-scuauth--root-flow-l3)
5. [Exception System](#5-exception-system)
6. [AuthState Enum](#6-authstate-enum)
7. [AuthCoordinator (L2 scheduler)](#7-authcoordinator-l2-scheduler)
8. [SubsystemAuth Contract + SsoRelayAuth Base](#8-subsystemauth-contract--ssorelayauth-base)
9. [Subsystem Auth Implementations](#9-subsystem-auth-implementations)
   - [ZhjwAuth](#91-zhjwauth)
   - [WfwAuth](#92-wfwauth)
   - [PayAppAuth](#93-payappauth)
   - [FitnessAuth](#94-fitnessauth)
   - [CcylAuth + CcylOAuthService](#95-ccylauth--ccyloauthservice)
   - [ZhhqAuth](#96-zhhqauth)
   - [ServiceAuth](#97-serviceauth)
   - [NewServiceAuth](#98-newserviceauth)
10. [API Layer: retryOnUnauthenticated + looksLikeLoginPage](#10-api-layer-retryonunauthenticated--lookslikeloginpage)
11. [API Services Catalog](#11-api-services-catalog)
    - WfwApiService, ZhjwApiService (+ HTML parsers), PayAppApiService + BalanceQueryService, FitnessApiService, CcylApiService + CcylService, ZhhqApiService, ServiceApiService (+ form-engine models), NewServiceApiService, AcademicCalendarService, ForgotPasswordService
12. [ZhhqCrypto — exact algorithm + keys](#12-zhhqcrypto--exact-algorithm--keys)
13. [SM2Crypto — login password encryption](#13-sm2crypto--login-password-encryption)
14. [Storage Keys Catalog](#14-storage-keys-catalog)
15. [UserInfo — where name / student id come from](#15-userinfo--where-name--student-id-come-from)
16. [AuthLogger](#16-authlogger)
17. [JSON Utils (parseJson / safe accessors)](#17-json-utils)
18. [DI / Lifecycle Wiring](#18-di--lifecycle-wiring)
19. [Swift Porting Notes (gotchas checklist)](#19-swift-porting-notes)

---

## 1. Global Constants

File: `lib/utils/constants.dart`

| Constant | Value | Notes |
|---|---|---|
| `kHttpTimeout` | `Duration(seconds: 15)` | Default timeout for ALL HTTP (root auth, subsystem SSO, business APIs). Exception: zhhq image upload = 30 s. |
| `kCcylSpCode` | (long base64 string, quoted verbatim below) | OAuth `sp_code` for CCYL SSO relay. |
| `kDefaultUserAgent` | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0` | Desktop Edge UA — spoofed on every request. Single line string in Dart (concatenated). |
| `kZhjwBase` (declared in `scu_auth.dart`) | `http://zhjw.scu.edu.cn` | **PLAIN HTTP** — the jwxt server does not support HTTPS. ATS exception required in iOS. |

`kCcylSpCode` verbatim:

```
bDBhREE1WDMzK3llSzZyVFZNeE81czRDd1hESTI4NWxGaFdsTnlvcGt3eVdTb2cxSjN5a1FJTDVMWTBEQkFFd2k1bWZRMy82OXN6V21ZYzFLd2NlSDdUaWlVcVJ1emxVVnF4Q3RZNWxjWlVoTEZqUktVSWVmY1ZaKzBLYUlBWDYvaU5MS1E5Y25nT1BoSzRIM0FIOWVCQjMxMXd5b0JrenNuWDBDM1BKU0FwUVVnZHdoSWYrc0hKZmEwSHRQbFZDV1o2dzFtQ3Nuci9wV1ExZHRMMytueHpLZVg5djJJcGFRbkJxZFJCQWJZWHI2dlpQNHVxNFNhcHM3Y3RkK2g1dWFuUEtNT1JZblFXRFBLUEdrcGdxNHR5eEcxclh5YXQ5a2FXN3JSZ2g2OTAxWCt0TUdTNXJDRVdNeDNTU3duTk1nNW9RSyt4WkdzSjNkR3NvVEFDMzFCQmJHUVcrVitybmszQVd0djFpUUJ5dDJySlRTajZIem1qZFYwMjVWcVpEaUtKd1AwQzI3TUpZd3FyY1hqdkxUZkFCd3JwL3ltczdXcmlTUzhZYVJPR0QwOXk2aDJIdUlCUTAvbEJWd0xzcUZXSElxaENpR0pseG1XYTZRbWlFaklERTd6TlhBQkJLdTZGUS8rNTBBYWRkcDVrRXdBM0tqejMvd1AvTklkZW5oNll4MllINlFiNVRucXNhZWtzUlh3d1BOQzBrMERSM0tId3dyS1hONkF6VDZwRGl3S3h1aDNLSGVmcTBRTktXUXMxTTZxeW1lcmgzYVlGWDNmVHdvUnJkWXVhbHN0aEtHKzU5TnFuVm1NbXU4dnhZQk8zKzQrdnV3aTJEaGY4VXRnV3lHeTVBcFFnWlUyQTFsWjdsR1RyNHh1TjV5dUlVc1NNOVRlbEtETTVVYWZoYnFPTXFrM2MxUHVNSHVHLzRtUFk4cmZzaXNUVkovWlhuSkhWWXpZQUJ4UDE4bGt2NXJkMFlXZHM0cFlYVVduKy9ZWGNKTlBDNEVrSzE3R0NVWDNxcCtiQkVyaXMzaTRXam1wWTFzYkpWZTAxYzZ0VGlxcGkvcEYyLzJPND0=
```

Other constants in the file (UI dock ids, links, method channels) are not auth-related:
`orgLink = https://github.com/The-Brotherhood-of-SCU`, `appLink = .../Bugaoshan`,
`officialWebsiteLink = https://bugaoshan.scubro.dev/`, `userManualLink = https://bugaoshan-docs.scubro.dev/manual/`,
method channels `bugaoshan/update`, `bugaoshan/dynamic_icon`, event channel `bugaoshan/download_cancel`.

---

## 2. Three-Layer Architecture Summary

```
UI (Pages/Widgets)
 └─ L1 Providers (stateful: loading/error/data)  →  API Services (stateless: http/parse/expiry-detect/one-retry)
      └─ L2 SubsystemAuth implementations (per-subsystem session/token, single-flight login)
           + AuthCoordinator (dependency-aware background warm-up)
            └─ L3 ScuAuth (root token, principal, id.scu.edu.cn cookie session, TTL + auto refresh)
                 └─ Infra: CookieClient / FlutterSecureStorage / SharedPreferences / AuthLogger
```

Key invariants (from `docs/architecture/authentication.md` §16, must be preserved in Swift):

1. `ScuAuth` is the single source of truth for root token / principal / unified session.
2. L2 modules depend on each other only through explicit `dependencies`.
3. One L2 failure must not block unrelated modules.
4. Warm-up failure never permanently disables a module (on-demand auth still possible).
5. Concurrent calls to the same auth operation MUST be coalesced (single-flight).
6. A new root `CookieClient` identity invalidates subsystem session caches; business code must not trust `isReady` alone — always call `getClient()`.
7. After logout/account switch, in-flight async results must not restore sessions or overwrite the new account's data.
8. Auto-retry is bounded (one replay) and only for explicit auth-expiry signals.
9. Credentials only in secure storage; logs redacted before write.
10. Providers never implement token/cookie/SSO details.

---

## 3. CookieClient (transport layer)

File: `lib/services/auth/cookie_client.dart` — `class CookieClient extends http.BaseClient`

Swift port: this is an `URLSession` wrapper with a manual in-memory cookie jar, per-domain, plus a manual
redirect-following helper. Do NOT use `HTTPCookieStorage` shared storage blindly — the app deliberately
isolates cookies per client instance (each subsystem SSO uses the same client that holds the id.scu.edu.cn
session, so cookies must be shared *within one client*, but clients are per-login-generation).

### 3.1 Cookie jar semantics

- Storage: `Map<String /*host*/, Map<String /*cookie name*/, String /*value*/>> _jar`
- Cookies stored keyed by the **host of the response URL** (from `Set-Cookie` of that response).
- Outgoing cookie selection `_cookiesFor(uri)`: include jar entries whose key `jarHost` satisfies
  `host == jarHost || host.endsWith('.' + jarHost)` (exact host or parent domain).
- `Set-Cookie` parsing: split the raw header value on
  `RegExp(r',\s*(?=[A-Za-z][^,=\s]*\s*=)')` (comma only when followed by `name=`), then for each part take
  `part.split(';').first`, split on first `=`.
- Note: the http package exposes `set-cookie` as a single joined header; in Swift use
  `HTTPURLResponse.allHeaderFields` with case-insensitive lookup (join multiple `Set-Cookie` lines the same way).

### 3.2 Manual redirect following (`followRedirects`)

```dart
Future<http.Response> followRedirects(
  Uri url, {
  Map<String, String>? headers,
  Set<Uri> sensitiveHeaderAllowedOrigins = const {},
  int maxRedirects = 10,
})
```

- Loop up to `maxRedirects + 1` times (i.e. up to 11 requests, indices 0..10):
  - Build GET request with `followRedirects = false` (Swift: `URLSession` default follows redirects —
    implement `urlSession(_:task:willPerformHTTPRedirection:...)` delegate that cancels and returns the
    3xx response, or use the lower-level API).
  - Attach cookies for the *current hop's* host (`Cookie` header, joined `k=v; `).
  - Attach filtered headers (see 3.3).
  - Send via `sendWithClientExceptionRetry` (see 3.4); collect `Set-Cookie` into the jar for this host.
  - If `300 <= status < 400`:
    - `location = response.headers['location']`; if missing → break out and return the response.
    - `current = current.resolve(location)` — resolves relative Locations. `FormatException` →
      `ServiceException('SSO 重定向地址无法解析: $location')`.
    - Continue loop.
  - Else: return response.
- Exceeding max redirects → `ServiceException('SSO 重定向链超过上限', statusCode: lastResponse?.statusCode)`.

### 3.3 Sensitive header filtering on redirects

`_sensitiveRedirectHeaders = {'authorization', 'proxy-authorization', 'cookie'}` (lowercased compare).

For each hop, the caller-supplied `headers` are forwarded **in full** only if:
`_isSameOrigin(initialUrl, currentUrl)` OR `allowedOrigins.any(_isSameOrigin(origin, currentUrl))`
(same scheme+host+port, case-insensitive host/scheme). Otherwise the three sensitive headers are stripped
for that hop. (The `Cookie` header is re-derived per-hop from the jar anyway; the filter guards against
explicitly-passed cookie headers.)

**Critical for correctness**: the SSO entries pass `Authorization: Bearer <token>` for the *first* hop to
`id.scu.edu.cn`; cross-origin hops must NOT forward it (the CAS redirect chains go id.scu.edu.cn →
subsystem domain, and forwarding the bearer there is both a leak and breaks some servers).

### 3.4 ClientException retry

`sendWithClientExceptionRetry(request)`: on `http.ClientException`, close the inner client, create a new
`http.Client()`, rebuild the request (method, url, followRedirects flag, headers, body for `http.Request`),
resend once with the same 15 s timeout. Second failure propagates. (Swift analogue: retry once on
`URLError` `.networkConnectionLost` / similar transport errors with a fresh `URLSession`.)

### 3.5 Reusability / close

- `bool reusable = false` — set `true` by ScuAuth after a successful `session/save`.
- `close()` respects reusable (no-op for reusable clients); `closeForce()` always closes.
  Logout and client replacement must call `closeForce()`.

### 3.6 Plain `send()` override

Every ordinary request through the client: attach cookies for the request host, send (with the
ClientException retry), store response cookies, log `METHOD host path -> status`.

---

## 4. ScuAuth — Root Flow (L3)

File: `lib/services/auth/scu_auth.dart` (686 lines). `class ScuAuth extends ChangeNotifier`.

### 4.1 Constants

```dart
static const _base = 'https://id.scu.edu.cn';
static const _clientId = '1371cbeda563697537f28d99b4744a973uDKtgYqL5B';
static const _enterpriseId = 'scdx';
const _sessionDurationSeconds = 3600; // 1 hour local TTL
const kZhjwBase = 'http://zhjw.scu.edu.cn'; // top-level const in same file
```

Default request headers (used for captcha / sm2_key / rest_token / session/save):

```dart
{
  'Accept': 'application/json, text/plain, */*',
  'Content-Type': 'application/json;charset=UTF-8',
  'Origin': 'https://id.scu.edu.cn',
  'Referer': 'https://id.scu.edu.cn/frontend/login',
  'User-Agent': kDefaultUserAgent,
}
```

### 4.2 Endpoints

| Step | Method & URL | Body / Query | Response handling |
|---|---|---|---|
| Captcha | `GET https://id.scu.edu.cn/api/public/bff/v1.2/one_time_login/captcha?_enterprise_id=scdx&timestamp=<ms epoch>` | — | JSON. `data.captcha ?? data.image ?? data.img ?? data.captchaImage` → base64 image (data-URI with `,` possible); `data.code` → captcha id used as `cap_code`. Missing either → `ScuLoginException('验证码字段解析失败')`. Non-JSON (5xx/maintenance page) → `ScuLoginException('验证码接口请求失败(HTTP <code>)')`. |
| SM2 public key | `POST https://id.scu.edu.cn/api/public/bff/v1.2/sm2_key` body `'{}'` | — | JSON `data.publicKey` (base64, may lack `04` prefix — code prepends `0x04` if absent), `data.code` (the `sm2_code`). Server intermittently 500s → **3 attempts with 500 ms delay between**; all fail → `ScuLoginException('SM2 公钥接口返回异常')` / `'SM2 公钥字段缺失'`. |
| Login (token) | `POST https://id.scu.edu.cn/api/public/bff/v1.2/rest_token` | JSON: see 4.3 | Non-2xx → try `extractTokenErrorMessage(body)` (JSON keys in order: `message`, `msg`, `error_description`, `description`, `error`; first non-empty string wins) → `ScuLoginException(detail)`; else `ScuLoginException('登录请求失败(HTTP <code>)')`. 2xx → JSON must have `success == true`; else `ScuLoginException(message ?? msg ?? '登录失败')`. Token = `data.access_token` (string); missing → `ScuLoginException('Token 字段缺失')`. |
| Session save (bind) | `POST https://id.scu.edu.cn/api/bff/v1.2/commons/session/save` body `'{}'` | Header additionally: `Authorization: Bearer <accessToken>` | 401/403 → `UnauthenticatedException('统一认证 token 已失效')`. Non-2xx → `ServiceException('session/save 请求失败', statusCode)`. JSON `error == 'invalid_token'` (case-insensitive compare on `.toLowerCase()`) → Unauthenticated. `success != true` → `ServiceException('session/save 失败: <body>', statusCode)`. Success → the response `Set-Cookie`s (id.scu.edu.cn session cookies) are captured in the CookieClient; mark `client.reusable = true`, cache it. |
| Logout | — (no server call) | — | Purely local cleanup (see 4.8). |

Note: there is **no refresh-token endpoint** — "refresh" is either re-bind with the existing token or a
fresh full password login via `autoLogin()`.

### 4.3 Login request payload (exact)

```json
{
  "client_id": "1371cbeda563697537f28d99b4744a973uDKtgYqL5B",
  "grant_type": "password",
  "scope": "read",
  "username": "<student id>",
  "password": "<SM2 C1C2C3 base64, see §13>",
  "_enterprise_id": "scdx",
  "sm2_code": "<from sm2_key response data.code>",
  "cap_code": "<captcha.code from captcha response>",
  "cap_text": "<user-typed or OCR'd captcha text>"
}
```

On success the flow writes:

- `SecureStorage[kScuAccessToken] = token`
- `SecureStorage[kScuPrincipalBinding] = JSON {"principal": username, "tokenFingerprint": sha256hex(utf8(token))}`
- `SharedPreferences[kScuLoginTimestamp] = now_seconds`
- clears `_cachedClient` / `_bindSessionFuture`, sets `_principal = username`, `state = ready`.

### 4.4 Captcha OCR (auto-login only)

`autoLogin()` calls `fetchCaptcha()`, strips an optional data-URI prefix (everything up to and including
the first `,`), base64-decodes, and runs `OcrService.performOcr(bytes)`.

`OcrService` (lib/services/ocr_service.dart) wraps a **native plugin** `scu_ocr_lite`
(asset `packages/scu_ocr_lite/assets/model.scuocr`, initialized from bundled bytes, `recognizeAsync`).
→ For Swift: port the ONNX-lite model + wrapper, or substitute Vision framework; the login flow only
needs 4-5 char alphanumeric captcha recognition with decent accuracy (retries up to 5× on
`invalid_captcha` at provider level).

### 4.5 init() — cold-start restore

1. `_accessToken = SecureStorage[kScuAccessToken]` (errors swallowed → null).
2. `_principal = _restorePrincipal(token)`: reads `SecureStorage[kScuPrincipalBinding]`, decodes JSON,
   returns `principal` **only if** `tokenFingerprint == sha256hex(current token)`; on any mismatch/parse
   error the binding entry is deleted and principal is null.
3. `_loginTimestamp = SharedPreferences[kScuLoginTimestamp]`.
4. If token != null && !isExpired → `state = ready`. If token != null but expired → stays non-ready
   (first `getClient()` will attempt refresh). No token → stays `unknown`.

`isExpired`: `_loginTimestamp == null || (now_seconds - _loginTimestamp) > 3600`.

### 4.6 bindSession() + getClient() + getAccessToken()

`bindSession()`:
- Requires `_accessToken != null` else `UnauthenticatedException('未登录')`.
- Cache hit (`_cachedClient != null`) → return.
- Single-flight: if `_bindSessionFuture != null` return it; else run `_doBindSession()` and store the
  future; **cleared in `finally`** (so a *failed* bind is retried by the next caller).
- `invalidateCachedClient()` nulls `_cachedClient` (forces next bindSession to re-handshake).

`getClient()` decision tree:
1. `isExpired` → `_synchronizedRefresh()`; on false → `onSessionExpired?.call()` then
   `throw UnauthenticatedException()`; on true → `bindSession()`.
2. Token null → `UnauthenticatedException('未登录')`.
3. Try `bindSession()`:
   - `UnauthenticatedException` → refresh → (fail ⇒ onSessionExpired + throw) → `bindSession()` again.
   - `ServiceException` (non-auth failure of session/save) → also attempt one refresh (self-heal path)
     then `bindSession()` again.

`getAccessToken()` (used by WfwAuth-likes needing the Bearer string): same TTL check + refresh, then
returns the raw token (no bind).

### 4.7 Refresh: `_synchronizedRefresh()` / `_doRefresh()`

Single-flight via `Completer<bool> _refreshCompleter`:
- Existing completer → await its future.
- New: capture `epoch = _authEpoch`, run `_doRefresh()`, complete with bool result.
  On throw: if `_authEpoch == epoch` set `state = error`; complete with error; rethrow.
- Cleared in `finally` only if identical.

`_doRefresh()` sequence:
1. No token → `state = expired`, return false.
2. `invalidateCachedClient()` then try `bindSession()` with existing token. Success:
   - if `_authEpoch != epoch` (logout happened mid-flight) → close client, return false (do NOT write back).
   - else update `_loginTimestamp` (+persist), `state = ready`, return true.
3. Else `autoLogin()` (saved credentials + captcha OCR). Success + epoch match → `state = ready`, true.
4. Else `state = expired`, false.

External entry: `Future<bool> refresh() => _synchronizedRefresh()`.

### 4.8 logout() + authEpoch semantics

```dart
_authEpoch++;                              // generation counter
final pending = _refreshCompleter; _refreshCompleter = null;
if (pending != null && !pending.isCompleted) pending.complete(false);  // wake waiters with "failed"
_cachedClient?.closeForce();
_accessToken = _principal = _cachedClient = _bindSessionFuture = _loginTimestamp = null;
SecureStorage.delete(kScuAccessToken); SecureStorage.delete(kScuPrincipalBinding);
prefs.remove(kScuLoginTimestamp);
state = AuthState.unknown;
```

Semantics: any refresh that captured an older epoch must **discard** its result (checked in
`_doRefresh`/`_synchronizedRefresh`) — prevents an in-flight `autoLogin` from resurrecting the session
after logout. Swift port: an `Int` generation counter guarded on the actor/main-actor; capture at start,
compare before commit.

### 4.9 onSessionExpired callback

`VoidCallback? onSessionExpired` — invoked by `getClient`/`getAccessToken` when refresh ultimately
fails, immediately before throwing `UnauthenticatedException`. Registered by
`SessionExpiredListener` widget (shows a snackbar with "前往登录", 5 s cooldown to dedupe concurrent
requests). Swift port: a notification / closure on the auth actor; same cooldown idea.

### 4.10 Credentials management (for auto-login)

- `saveCredentials(u, p)`: `kScuRememberPassword='true'`, `kScuSavedUsername=u`, `kScuSavedPassword=p`.
- `getSavedCredentials()`: returns `{'username', 'password'}` only if remember == `'true'` and both exist.
- `clearCredentials()`: deletes the three keys.
- `autoLogin()` (ScuAuth-level, used inside refresh): one captcha+OCR+login attempt, returns bool.

`ScuAuthProvider.autoLogin()` (UI-level, lib/providers/scu_auth_provider.dart) is richer:
- Gated by `SecureStorage[kScuAutoLogin] == 'true'` and not already logged in and credentials present.
- Sets `isAutoLoggingIn = true` during the whole loop (UI gate).
- Up to `maxRetries = 5` attempts; on `ScuLoginException` with `e.message == 'invalid_captcha'` → retry
  with a fresh captcha; any other login error or OCR error → return false; other exceptions → false.
- After a successful login, `unawaited(_authCoordinator.warmUpAll())` kicks off background warm-up.

### 4.11 `extractTokenErrorMessage` (visibleForTesting)

```dart
String? extractTokenErrorMessage(String body) {
  // decode JSON; for key in ['message','msg','error_description','description','error']
  // return first non-empty String value; non-JSON → null
}
```

---

## 5. Exception System

File: `lib/services/auth/scu_exceptions.dart`. Sealed hierarchy `ScuException : Exception` with
`message`; `toString() => message`.

| Class | Default message | Extra fields | Meaning / retry behavior |
|---|---|---|---|
| `UnauthenticatedException` | `'未登录或登录已过期'` | — | Auth lost. L1 wrappers replay exactly once; then propagates to Provider → UI "go to login". |
| `ServiceException` | — | `int? statusCode` | Network/parse/non-200/business error. No auth auto-retry. |
| `RateLimitedException extends ServiceException` | `'rateLimited'` | — | Server rate limit (zhjw `请勿频繁刷新`). No auto-retry. |
| `ScuLoginException` | — | — | Login-page errors (captcha/credentials). Only UI auto-login retries, and only `invalid_captcha`, max 5×. |
| `ForgotPasswordException` | — | `int? businessCode` | Forgot-password business errors (400 captcha wrong, 439 captcha expired, etc.). |

CCYL adds its own (in `ccyl_service.dart`, NOT part of the sealed hierarchy): `CcylException` and
subclass `CcylAuthExpiredException` (business code 401 → token expired → CCYL wrapper retries once).
PayApp adds `BalanceQueryException` / (unused) `BalanceQueryAuthException`.

---

## 6. AuthState Enum

File: `lib/services/auth/auth_state.dart`

```dart
enum AuthState { unknown, ready, expired, error }
// unknown: not authenticated yet; ready: usable; expired: needs refresh; error: non-expiry failure
```

Transitions that matter (from architecture doc §5.4): TTL expiry does NOT immediately set `expired`;
refresh is attempted first and only its failure sets `expired`. `logout` → `unknown` from any state.

---

## 7. AuthCoordinator (L2 scheduler)

File: `lib/services/auth/auth_coordinator.dart`

- Holds `List<SubsystemAuth> _modules` (unmodifiable). 
- `warmUpAll()` single-flight via `_warmUpFuture`; on completion clears it only if still identical.
- `_warmUpAll()`: memoized `Future<bool>` per module (`futures` map). Recursive `ensure(auth, path)`:
  - Cycle detection: `path.contains(auth)` → log warn, return false.
  - `Future.wait(auth.dependencies.map(ensure))` — any dep failed → skip module (false).
  - `await auth.ensureAuthenticated()` → true; exception → log, false. Failures never throw to caller.
- `invalidateAll()`: clears `_warmUpFuture`, calls `module.invalidate()` for all.
- Called from: `ScuAuthProvider.login()` (unawaited, post-login) and home page cold-start auto-login
  recovery.

Swift port: a task map keyed by module id; use structured concurrency (`withTaskGroup` + per-module
`Task` memoization). Preserve cycle detection and failure isolation.

---

## 8. SubsystemAuth Contract + SsoRelayAuth Base

### 8.1 Contract (`lib/services/auth/subsystem_auth.dart`)

```dart
abstract interface class SubsystemAuth {
  String get moduleId;
  List<SubsystemAuth> get dependencies;   // only real L2 deps; SCU root NOT listed
  Future<void> ensureAuthenticated();
  void invalidate();
}

Future<void> ensureAuthDependencies(Iterable<SubsystemAuth> dependencies) =>
    Future.wait(dependencies.map((a) => a.ensureAuthenticated()));
```

### 8.2 SsoRelayAuth base (`lib/services/auth/sso_relay_auth.dart`)

Abstract base for "subsite gets its cookies by following an SCU SSO URL with the Bearer token".
Used by PayAppAuth, FitnessAuth, ServiceAuth, NewServiceAuth.

State: `_cachedClient`, `_lastScuClient` (identity check), `_loginFuture` (single-flight), `_isReady`.

`getClient()` flow:
1. `await ensureAuthDependencies(_dependencies)`.
2. `scuClient = await _scuAuth.getClient()`.
3. `if (!identical(scuClient, _lastScuClient))` → root client changed → clear `_cachedClient`,
   `_loginFuture`, set `_lastScuClient = scuClient`. (Swift: compare object identity / generation id.)
4. Cache hit → return. In-flight `_loginFuture` → await it.
5. `_login(scuClient)`:
   - Requires `_scuAuth.accessToken != null` else Unauthenticated.
   - `scuClient.followRedirects(Uri.parse(_ssoUrl), headers: { 'Accept': 'text/html,application/xhtml+xml,*/*', 'User-Agent': kDefaultUserAgent, 'Authorization': Bearer <token> })`.
   - Final status 401/403 → `UnauthenticatedException()`.
   - Status <200 or >=400 → `ServiceException('<moduleId> SSO 中继失败', statusCode)`.
   - Success: `_cachedClient = scuClient` (the SAME client — subsite cookies now live in the shared root
     client's jar), `_isReady = true` + notify once.
6. `_loginFuture` cleared in `finally`.

`invalidate()`: clears cached client, login future, `_lastScuClient`, `_isReady = false`.
Listens to `_scuAuth` and resets `_isReady` when root leaves ready (`!_scuAuth.isReady`), forwarding
notifications. `isReady` is a UI hint only — requests must still call `getClient()`.

---

## 9. Subsystem Auth Implementations

### 9.1 ZhjwAuth

File: `lib/services/auth/zhjw_auth.dart`. moduleId `'zhjw'`, dependencies `[]`. `ChangeNotifier` that
forwards `_scuAuth.addListener(notifyListeners)` (no filtering — every ScuAuth notify re-notifies).

SSO URL (exact):

```
https://id.scu.edu.cn/enduser/sp/sso/scdxplugin_jwt23?enterpriseId=scdx&target_url=index
```

`_login(client)` → `client.followRedirects(url, headers: {Accept: 'text/html,application/xhtml+xml,*/*',
User-Agent, Authorization: Bearer <token>})` → 401/403 ⇒ Unauthenticated; other non-2xx/3xx-final
⇒ `ServiceException('教务 SSO 登录失败', statusCode)`; success caches the client.

Single-flight `_loginFuture`; identity check against `_lastScuClient` (root client swap ⇒ clear cache +
re-SSO). `invalidate()` clears `_cachedClient`/`_loginFuture` (note: does NOT reset `_lastScuClient`,
unlike SsoRelayAuth — harmless because identity is re-checked against the new root client).
No `isReady` flag. Result: zhjw session cookie (Spring Security `JSESSIONID`-family) lives in the shared
client's jar under `zhjw.scu.edu.cn`.

### 9.2 WfwAuth

File: `lib/services/auth/wfw_auth.dart`. moduleId `'wfw'`, deps `[]`. Session = wfw cookies in the
**shared root CookieClient** (`eai-sess` etc. on `wfw.scu.edu.cn`). WfwApiService uses
`_scuAuth.getClient()`'s client directly (see `getClient()` below: returns the *root* client after
ensuring warm-up — NOT a separate client).

`ensureAuthenticated()` / `getClient()` = `final client = await _scuAuth.getClient(); await _ensureClientReady(client); return client;`

`_ensureClientReady`:
- identity check vs `_lastScuClient`; changed → `_ready = false`, clear `_warmUpFuture`.
- If ready → return.
- single-flight `_warmUpFuture` → `_warmUp(client)`:

`_warmUp` (the critical, trap-laden bit — quote from code comments):
- URL: `const warmUpUrl = 'https://wfw.scu.edu.cn/uc/wap/user/get-info';`
- GET via `client.followRedirects` with ONLY `{'User-Agent': kDefaultUserAgent}` — **no AJAX header**.
  Anonymous chain: get-info → 302 `/uc/wap/login` → `/a_scu/api/cas/login` → id.scu.edu.cn CAS → back to
  wfw, establishing the bound session cookie in the shared jar. Already bound: direct `e==0` JSON.
- **Must NOT warm up with the wfw homepage**: anonymous homepage returns 200 + anonymous `eai-sess`
  cookie and never triggers SSO — judging readiness by status code or "jar has wfw cookies" would
  misreport an anonymous session as ready → infinite invalidate/re-warm loop.
- Readiness criterion: final response is JSON with `e == 0` (`_isBoundSessionBody`). 401/403 →
  `UnauthenticatedException('微服务登录已失效')`; other non-2xx → `ServiceException('微服务预热失败')`;
  non-JSON / `e != 0` → `UnauthenticatedException('微服务 session 未建立')`.
- Listens to ScuAuth: on `AuthState.unknown` → `_ready = false`, `_lastScuClient = null`,
  `_warmUpFuture = null`, notify.

`state` getter: `_ready ? ready : unknown`.

### 9.3 PayAppAuth

File: `lib/services/auth/payapp_auth.dart`. `class PayAppAuth extends SsoRelayAuth`.

SSO URL: `https://payapp.scu.edu.cn/eleFees/oauth/airWarrant` — dependencies: `[wfwAuth]`.
Resulting login-state cookie: `airWarrant` on payapp.scu.edu.cn. moduleId `'payapp'`.

### 9.4 FitnessAuth

File: `lib/services/auth/fitness_auth.dart`. `extends SsoRelayAuth`, no deps.

SSO URL (exact):
```
https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php/index/login/scuMsLogin
```
moduleId `'fitness'`.

### 9.5 CcylAuth + CcylOAuthService

Files: `lib/services/auth/ccyl_auth.dart` (301 lines), `lib/services/auth/ccyl_oauth_service.dart`,
`lib/services/ccyl/ccyl_service.dart` (login + API, see §11.5).

CCYL (第二课堂, `dekt.scu.edu.cn`) has an **independent OAuth token system** — no shared cookies.

Storage keys (private consts in ccyl_auth.dart):
```dart
const _keyCcylToken = 'ccyl_token';      // legacy, deleted on init
const _keyCcylUserId = 'ccyl_user_id';   // legacy, deleted on init
const _keyCcylSession = 'ccyl_session_v2'; // current: JSON {token, userId, scuPrincipal}
```

State: `_token`, `_currentUser` (`CcylUser{id, userName, realname, orgName}`), `_boundScuPrincipal`,
`_reLoginFuture` (single-flight), `_authGeneration` (int, like ScuAuth epoch), `_storageTail`
(chained future serializing secure-storage writes).

Principal binding — every getter is gated:
```dart
bool get _isBoundToCurrentPrincipal =>
    _token != null && _boundScuPrincipal != null && _boundScuPrincipal == _scuAuth.principal;
String? get token => _isBoundToCurrentPrincipal ? _token : null;
bool get isLoggedIn => _isBoundToCurrentPrincipal;
CcylUser? get currentUser => _isBoundToCurrentPrincipal ? _currentUser : null;
```

`init()`: deletes legacy keys; reads `ccyl_session_v2`; restores only if persisted
`scuPrincipal == _scuAuth.principal` (and both non-null); otherwise wipes. Restored user is a stub
(`userName/realname/orgName` empty — filled on next real login).

`ensureAuthenticated()`: if bound → return; if any stale state → `invalidateSession()`; then `reLogin()`;
failure → `UnauthenticatedException('第二课堂未登录')`.

`loginWithCode(code)` (manual authorization path): `++_authGeneration`, requires `_scuAuth.principal`
(else `UnauthenticatedException('无法确认当前校园账号，请重新登录')`), calls
`CcylService.login(code)` → `{token, user}`; result committed only if generation AND principal still
match; commit = serialized secure-storage write of `ccyl_session_v2` + delete legacy keys; then memory
fields set; notify.

`reLogin()` (silent OAuth re-bind, single-flight `_reLoginFuture`):
1. principal must be available and attempt current.
2. `oauthCode = await CcylOAuthService(_scuAuth).getOAuthCode()` (or injected provider).
3. `CcylService.login(oauthCode)`; commit like above.

`recoverExpiredSession()` — single-flight shared by concurrent expiry: bumps generation (cancels current),
clears persisted session, runs `_doReLogin(generation)`.

`invalidate()` / `invalidateSession()` / `logout()`: bump generation, clear memory (+ persisted for the
latter two), notify (logout only).

**CcylOAuthService.getOAuthCode()** (ccyl_oauth_service.dart):

- Requires `_scuAuth.accessToken`; gets a root CookieClient via `_scuAuth.getClient()`.
- URL (exact):
```
GET https://id.scu.edu.cn/api/bff/v1.2/commons/sp_logged?access_token=<token>&sp_code=<kCcylSpCode>&application_key=scdxplugin_cas_apereo17
```
- Follows redirects (headers: `Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*`,
  `User-Agent`).
- Extracts OAuth `code` from (a) the final URL's `code=` query param (`response.request?.url`), else
  (b) a redirect URI found in the response body:
  - meta refresh: `<meta[^>]+http-equiv=["']refresh["'][^>]+content=["'][^;]+;\s*url=([^"'>\s]+)` (case-insensitive)
  - JS: `window\.location(?:\.href)?\s*=\s*["']([^"']+)["']`
- Returns null on any failure. Client closed in `finally` (non-force — it's the reusable root client,
  so `close()` is a no-op).

### 9.6 ZhhqAuth

File: `lib/services/auth/zhhq_auth.dart` (304 lines). 智慧后勤 smart logistics, `zhhq.scu.edu.cn`.
Login state = zhhq-domain `tokenKey` (the `ITSOFT-WILAB-SESSION` value), persisted at `kZhhqTokenKey`.

Constants:

```dart
static const String casUrl =
    'https://id.scu.edu.cn/enduser/sp/sso/scdxplugin_jwt31?enterpriseId=scdx';
static const String _loginAutoUrl = 'https://zhhq.scu.edu.cn/api/auth/login/auto';
```

Auth flow (packet-capture-confirmed per comments):
1. `client.followRedirects(casUrl, headers: {Accept: text/html..., User-Agent, Authorization: Bearer})`.
   401/403 → Unauthenticated; other non-2xx → `ServiceException('zhhq SSO 中继失败')`.
2. Final redirect lands on `zhhq.scu.edu.cn/account/login?userinfo=<encrypted>`; parse
   `userinfo` from `response.request?.url.queryParameters['userinfo']`. Missing →
   `UnauthenticatedException('zhhq 认证回跳缺少 userinfo')`. (Log only presence+length, never the URL.)
3. `POST https://zhhq.scu.edu.cn/api/auth/login/auto`, headers:
```
Accept: application/json, text/plain, */*
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Origin: https://zhhq.scu.edu.cn
Referer: https://zhhq.scu.edu.cn/account/login
User-Agent: <kDefaultUserAgent>
X-Requested-With: XMLHttpRequest
```
   form body (note `userInfo` is additionally URL-encoded):
```
userInfo   = Uri.encodeComponent(<userinfo from SSO>)
clientId   = 'web201911chengdu'
timestamp  = ZhhqCrypto.encrypt(<ms epoch as string>)     // AES with DEFAULT key/iv
schoolCode = '10610'
schoolName = '四川大学'
```
4. Response body is itself AES-encrypted JSON (`{data, errorCode, message, status}` via
   `zhhqDecodeResponse`). Status 302/401/403 or empty body → Unauthenticated. Parse failure →
   `UnauthenticatedException('zhhq tokenKey 获取失败')`. `errorCode != '0' && errorCode.isNotEmpty && status == 'error'`
   → `UnauthenticatedException('zhhq 登录失败: <message>')`. `data` = tokenKey; must be `>= 16` chars.
5. `_applyTokenKey`: memory + `SecureStorage[kZhhqTokenKey]` write, `_ready = true`, clear `_authFailed`.

Special behaviors:
- `init()` restores tokenKey unconditionally (does NOT wait for SCU): tokenKey is zhhq-domain state,
  business requests need only Token/TokenKey headers → cold-start fast path. Known edge: stale tokenKey
  from before a logout self-heals via 4010-4017 handling in the API layer.
- `_onScuAuthChanged`: on `AuthState.unknown` → clear tokenKey + persisted key + `_authFailed`.
- `ensureAuthenticated()`: fast path — if `_tokenKey != null` return immediately (no SCU wait; the
  id.scu.edu.cn SSO leg can take 5-8 s).
- `getClientFast()`: if tokenKey present, returns a brand-new empty `CookieClient` (zhhq business
  requests carry no cookies) — used by ZhhqApiService's fast path.
- `getClient()`: full path — `_scuAuth.getClient()` then `_ensureTokenKey(client)` (single-flight
  `_warmUpFuture`; failure sets `_authFailed = true` + notify + rethrow so pages can show retry).
- `invalidate()` (called by API layer on errorCode 4010-4017): clears tokenKey in memory AND secure
  storage, `_ready = false`.

### 9.7 ServiceAuth

File: `lib/services/auth/service_auth.dart`. `extends SsoRelayAuth`, no deps. moduleId `'service'`.
网上办事大厅 (online service hall) on `service.scu.edu.cn`.

SSO URL (exact):
```
https://service.scu.edu.cn/api/login/main?redirect_url=https%3A%2F%2Fservice.scu.edu.cn%2Fv2%2Fmatter%2F
```

Login-state cookies (capture-confirmed, on service.scu.edu.cn domain):
- `PHPSESSID=ST-<ticket>` — CAS ticket used directly as PHP session id
- `vjuid` — user uid (the `checkLogin()` criterion)
- `vjvd` — checksum
- `vt` — timestamp

SSO chain: `/api/login/main` (301) → `/site/login/cas-login` (302) → id.scu.edu.cn CAS plugin (Bearer)
→ back to service.scu.edu.cn with Set-Cookie of the above.

### 9.8 NewServiceAuth

File: `lib/services/auth/new_service_auth.dart`. `extends SsoRelayAuth`, no deps. moduleId `'newservice'`.
智慧线上服务平台 (new portal) at `service.scu.edu.cn/newservice`.

SSO URL (exact, note duplicated `platform_id` param — intentional, mirrors browser):
```
https://service.scu.edu.cn/newservice/api/login/cas?redirect_url=https%3A%2F%2Fservice.scu.edu.cn%2Fnewservice%2Ffe%2Fsite%2Fm_passpoint%3Fplatform_id%3D31%26platform_id%3D31
```

Login-state cookies (independent of the `vjuid` session): `process_uid` (uid, session criterion for
passpoint APIs), `process_number` (student/staff id).

---

## 10. API Layer: retryOnUnauthenticated + looksLikeLoginPage

File: `lib/services/api/api_request.dart`.

### 10.1 `retryOnUnauthenticated<T, C>(getClient, fn, {invalidate})`

```dart
try { final client = await getClient(); return await fn(client); }
on UnauthenticatedException {
  invalidate?.call();                       // clear L2 cache
  final client = await getClient();         // re-auth
  return await fn(client);                  // replay EXACTLY once
}
```
Second failure propagates. Only `UnauthenticatedException` triggers this — never `ServiceException`,
`RateLimitedException`, or CCYL's generic `CcylException`.

### 10.2 `looksLikeLoginPage(String body)`

HTML-only login-page detection (used by zhjw / wfw / newservice expiry checks). Steps:

1. HTML sentinel: `if (!body.trimLeft().startsWith('<')) return false;` — pure JSON/text never matches.
2. Lowercase the whole body.
3. Four strong features (any hit ⇒ login page):
   - **Title**: `<title[^>]*>([^<]*)</title>` — captured title contains `登录` OR matches `\blogin\b`.
   - **Spring Security form**: `<form[^>]+action\s*=\s*["'][^"']*j_spring_security_check` (must be inside
     a `<form action>`, not just mentioned in JS text).
   - **meta refresh / JS redirect to login URL**:
     `content\s*=\s*["'][^"']*url=([^"'>\s]+)` and
     `location\s*\.\s*(?:href|replace|assign)\s*[=(]\s*["']([^"']+)["']` — captured URL must match `\blogin\b`.
   - **Form action to login URL**: `<form[^>]+action\s*=\s*["']([^"']*)["']` — non-empty action matching `\blogin\b`.
4. Deliberately NOT used: `type="password"` (change-password pages also have it) and bare substring
   `login` (`loginStatus`, `clientLogin` false positives — issue #282).

`\blogin\b` semantics: `/login`, `/cas/login?service=…`, `login.aspx` match; `loginStatus`/`clientLogin` don't.

---

## 11. API Services Catalog

### 11.0 Shared conventions

- Every service: `_request(fn) = retryOnUnauthenticated(_auth.getClient, fn, invalidate: _auth.invalidate)`.
- All requests send `User-Agent: kDefaultUserAgent` and site-appropriate `Referer`/`Origin`.
- JSON helpers from `lib/utils/json_utils.dart`: `parseJson(body, api, exceptionFactory)` (throws the
  factory's exception with message `[<api>] 响应解析失败`, debug-prints a ≤200-char preview),
  `parseJsonList` (same for arrays), plus lenient accessors `safeDouble/safeInt/safeString/safeBool`
  (strings parsed, null/type mismatch → fallback; `safeBool` accepts 1/0, 'true'/'false').

### 11.1 WfwApiService

File: `lib/services/api/wfw_api_service.dart`. Depends on: **WfwAuth** (returns the shared root
CookieClient with warmed wfw session). Base: `https://wfw.scu.edu.cn`.

Response envelope: `{e: int, m: string, d: {...}}`; success ⇔ `e == 0` (compared as int OR string '0').

Expiry detection `_decodeResponse`:
- Status 302 / 401 / 403 or empty trimmed body → `UnauthenticatedException()`.
- `looksLikeLoginPage(body)` → Unauthenticated.
- `e == 10013` (int or string) → `UnauthenticatedException('微服务登录已失效')` (wfw's business
  session-expired code).

| Endpoint | Method | Headers (beyond UA) | Params | Result |
|---|---|---|---|---|
| `https://wfw.scu.edu.cn/mashupapp/wap/real/user` | GET | `Accept: application/json…`, `X-Requested-With: XMLHttpRequest`, `Referer: https://wfw.scu.edu.cn` | — | `d.labels` → `List<Map>` (user info labels) |
| `https://wfw.scu.edu.cn/uc/wap/user/get-info` | GET | (default only) | — | `d.base` → `Map?` (user profile: realname, role.number, …) |
| `$_baseUrl/netclient/wap/default/get-index` | POST | `_networkHeaders`: Accept json, `Content-Type: application/json; charset=UTF-8`, Origin/Referer = base, X-Requested-With | (empty JSON POST, no body sent) | `d.list` → list of campus-network online devices |
| `$_baseUrl/netclient/wap/default/offline` | POST | same + `Content-Type: application/x-www-form-urlencoded` | form: `device_id`, `ip` | success ⇔ `e==0`; else `ServiceException(m)` |

Business error helper: `_isSuccess(json) => json['e'] == 0 || '0'`; error message from `json['m']`.

### 11.2 ZhjwApiService

File: `lib/services/api/zhjw_api_service.dart` (1012 lines) + `part` file `zhjw_html_parsers.dart`.
Depends on: **ZhjwAuth**. Base: `kZhjwBase = http://zhjw.scu.edu.cn` (HTTP!).

Expiry detection `_checkSessionExpiry(body, statusCode)`:
- status 302 → Unauthenticated
- trimmed body empty → Unauthenticated
- `looksLikeLoginPage(body)` → Unauthenticated

Rate limit marker: body contains `请勿频繁刷新` → `RateLimitedException()`.
`static Duration planDetailRequestGap = Duration(milliseconds: 600)` — sleep between multi-plan detail
page fetches to avoid the rate limit.

#### Endpoints

| Purpose | Method & Path | Params | Parsing |
|---|---|---|---|
| Current teaching week | GET `/` | headers `Accept: text/html,*/*`, `Referer: $base/` | Regex `第(\d+)周` → int; if body contains `当前处于假期时间` → return null (vacation); else `ServiceException('无法获取当前周数…')` |
| Semester list | GET `/student/courseSelect/calendarSemesterCurriculum/index` | same | Regex `<option[^>]+value="([^"]+)"[^>]*>(.*?)</option>` (dotAll); label stripped of tags via `replaceAll(RegExp(r'<[^>]+>'), '')`. Empty → ServiceException |
| Semester schedule (jwxt) | POST `/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback` | form `planCode=<e.g. 2025-2026-2-1>`; headers: Accept json, `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`, Referer = calendarSemesterCurriculum/index, X-Requested-With | `parseJson` → raw Map |
| Passing scores | GET `/student/integratedQuery/scoreQuery/allPassingScores/index` then GET extracted callback | two-step: regex `var\s+url\s*=\s*"(/student/integratedQuery/scoreQuery/[^/]+/allPassingScores/callback)"` from index HTML; then GET that path | callback body `parseJson` → Map. Regex miss: if login page → Unauthenticated else `ServiceException('无法从页面提取 allPassingScores callback URL')` |
| Scheme scores | GET `/student/integratedQuery/scoreQuery/schemeScores/index` + callback | regex `var\s+url\s*=\s*"(/student/integratedQuery/scoreQuery/[^/]+/schemeScores/callback)"` | same pattern |
| Classroom index | GET `/student/teachingResources/classroomUseStatus/index` | — | `<input[^>]+id="xqList"[^>]+value='([^']+)'` → JSON array of campuses; `<input[^>]+id="jxlList"[^>]+value='([^']+)'` → buildings (single-quoted attr values!) |
| Classroom types | GET `/student/teachingResources/classroomUseStatus/<campusNumber>/<buildingNumber>/<enc(campusName)>/<enc(buildingName)>` | path segments | `<input[^>]+id="classroomTypes"[^>]+value='([^']+)'` → JSON list; no match → empty list |
| Classroom availability | POST `/student/teachingResources/classroomUseStatus/jasInfo` | form: `xqh, jxlh, jslx, jasm, zwFrom, zwTo, searchDate` (all urlencoded) | `parseJson` → `ClassroomQueryResult.fromJson` |
| Colleges (train program) | GET `/student/comprehensiveQuery/search/trainProgram/index` | — | `_parseOptions(body, 'xsh')`: select named `xsh`, `<option value>` → `College{value, name}` |
| Grades | GET same index page | — | `_parseGradeOptions(body, 'nj')` → `Grade{value, label}` |
| Search programs | POST `/student/comprehensiveQuery/search/trainProgram/load` | form string: `famc=&jhmc=&nj=<grade>&xw=&xzlx=&xdlx=00001&xsh=<college>&pageNum=1&pageSize=100` | `json['data']['records']` → `TrainProgram` list |
| Program detail | POST `.../trainProgram/detail` | form `fajhh=<id>&lx=1` | JSON → `TrainProgramDetail` |
| Course detail | GET `<urlPath>` (absolute path from program record) | — | JSON → `CourseDetail` |
| Plan completion | GET `/student/integratedQuery/planCompletion/index` (+ per-plan GETs) | — | see §11.2.1 (complex, multi-branch) |
| Exam plan | GET `/student/examinationManagement/examPlan/index` | — | `_parseExamCards(body)` — see §11.2.2 |
| Class-schedule inquiry index | GET `/student/teachingResources/classCurriculum/index` | — | `_parseSelectOptions` for `executiveEducationPlanNum` (semesters), `yearNum` (grades), `departmentNum` (departments) |
| Subjects by department | GET `/student/teachingResources/gradeAndClassCurriculum/subjectJson?departmentNum=<enc>` | X-Requested-With | JSON array → `SubjectOption` |
| Classes | GET `.../gradeAndClassCurriculum/classJson?departmentNum=<>&subjectNum=<>&yearNum=<>` | X-Requested-With | JSON array → `ClassOption` |
| Class list search | POST `/student/teachingResources/classCurriculum/search` | form: `executiveEducationPlanNum, yearNum, departmentNum, subjectNum, classNum, pageNum, pageSize` (default 30) | body is a JSON **array**: `json[0].records` + `json[0].pageContext.totalCount` |
| Class schedule | GET `.../classCurriculum/searchCurriculumInfo/callback?planCode=<>&classCode=<>` | X-Requested-With | JSON array; `json[0]` is itself the list of items |
| Course curriculum index | GET `/student/teachingResources/courseCurriculum/index` | — | selects: `zxjxjhh` (semesters), `kkxsh` (departments), `kclb` (categories) |
| Course list search | POST `/student/teachingResources/courseCurriculum/search` | form: `zxjxjhh, kkxsh, kcm, kch, kxh, kclb, pageNum, pageSize` | `parseJson` → `json.records` + `json.pageContext.totalCount` → `CourseSectionInfo` |
| Course schedule | GET `.../courseCurriculum/searchCurriculum/callback?planCode=<>&courseCode=<>&courseSequenceCode=<>` | X-Requested-With | JSON `[[items…]]` — outer array's first element is the item list (`parseJsonList` then `json.first` must be List) |

`_parseSelectOptions(html, selectId)` regexes (shared by the three index parsers):

```
<select[^>]*name="<selectId>"[^>]*>([\s\S]*?)</select>
<option[^>]*value="([^"]*)"[^>]*>([\s\S]*?)</option>   (inside select block; skip empty values; strip inner tags from label)
```

#### 11.2.1 Plan completion multi-branch parse (zhjw_html_parsers.dart)

`fetchPlanCompletion()` logic:
1. GET index. If body contains `请勿频繁刷新` → `RateLimitedException`. Then `_checkSessionExpiry`.
2. `_tryParseZNodes(body)` — regex `var\s+zNodes\s*=\s*(\[.*?\]);` (dotAll). Null when regex misses
   (maybe selection page); throws ServiceException on JSON/field parse failure.
   Non-empty nodes → single-plan: `[PlanCompletionPlan(id: '', name: _extractPlanName(body), nodes)]`.
3. Else `_extractPlanLinks(body)` (below). Non-empty → for each link (with `planDetailRequestGap`
   delay between requests, starting from the 2nd): GET
   `/student/integratedQuery/planCompletion/getPyfaIndex/<id>` (Referer = index page);
   each detail: `_checkSessionExpiry`, rate-limit check, `_parseZNodes` (throws on miss).
4. No nodes and no links: if `directNodes != null` (regex matched but empty array) → return `[]`
   ("account has no plan").
5. Otherwise structural anomaly: if `looksLikeLoginPage(body)` → Unauthenticated; else
   `ServiceException('方案修读数据格式异常：页面无法解析')` (deliberately NOT auth-refresh, to avoid
   re-SSO storms hitting the rate limiter).

`_extractPlanName(html)`: regex `data:\s*\[\s*'([^']+)'\s*\]` (echarts radar legend), truncated to 60
chars, `''` fallback.

`_extractPlanLinks(html)` — three tiers (dedup by id; name fallback `方案<id>`):
1. Buttons: `onclick=["'][^"']*getPyfaIndex\(\s*(?:&#39;|&quot;|['"])?(\d+)(?:&#39;|&quot;|['"])?\s*\)`
   (dotAll). Name from the enclosing `<button …>` tag's `title="…"` attr (search backwards
   `html.lastIndexOf('<button', m.start)` to `indexOf('>', m.start)`), stripping trailing `(\d+)\s*$`.
   Note the onclick quotes are HTML entities `&#39;` in real pages.
   Path: `/student/integratedQuery/planCompletion/getPyfaIndex/<id>`.
2. Anchors (only if no buttons): `<a[^>]*href=["'][^"']*getPyfaIndex/(\d+)[^"']*["'][^>]*>(.*?)</a>`
   (dotAll); strip tags + `&nbsp;` → spaces.
3. Bare ids (only if still empty): `getPyfaIndex/(\d+)`.

#### 11.2.2 Exam cards parse (`_parseExamCards`)

Block splitter regex (dotAll):
```
<div class="widget-box widget-color-\w+(?: collapsed)?">(.*?)</div>\s*</div>\s*</div>\s*</div>
```
Per block, first-match extraction:

| Field | Regex | Fallback |
|---|---|---|
| courseName | `<h5 class="widget-title smaller">\s*(.*?)\s*</h5>` then strip `\s*（已结束）` | `'未知'` |
| week | `(\d+)周` | `''` (displayed as `第 N 周` / `'未知'`) |
| date | `(\d{4}-\d{2}-\d{2})\s*&nbsp;` | `'未知'` |
| weekday | `(星期[一二三四五六日])` | `'未知'` |
| timeRange | `&nbsp;(\d{2}:\d{2}-\d{2}:\d{2})` | `'未知'` |
| location | `地点:&nbsp;(.+?)</br>` then `&nbsp;`→space | `'未知'` |
| seatNumber | `座位号:&nbsp;(\d+)` | `'未知'` |
| ticketNumber | `准考证号:&nbsp;(.*?)</br>` | `''` |
| tip | `考试提示信息：&nbsp;(.*?)</span>` | `'无'` |

### 11.3 PayAppApiService + BalanceQueryService

Files: `lib/services/api/payapp_api_service.dart`, `lib/services/api/balance_query_service.dart`.
Depends on: **PayAppAuth** (thus transitively WfwAuth). Base: `https://payapp.scu.edu.cn/eleFees`.

`PayAppApiService` is a thin wrapper over a stateless `BalanceQueryService` (constructed internally);
all methods route through `_request` (auth retry) with the SSO'd client.

Default headers (BalanceQueryService):
```
Accept: application/json, text/plain, */*
Content-Type: application/json;charset=UTF-8
Origin: https://payapp.scu.edu.cn/eleFees
Referer: https://payapp.scu.edu.cn/eleFees
User-Agent: <kDefaultUserAgent>
```

Response envelope: `{respCode: "00" means success, respDesc, data: {datas: [...] | status | …}}`.

Endpoints (all POST):

| Purpose | Path | Body | Result |
|---|---|---|---|
| Campus list | `/eleFees/electric/getCampus` | `'{}'` | `data.datas` → `[{name, code}]` |
| Buildings | `/eleFees/electric/getArchitecture` | `{"schoolCode": …}` | `data.datas` → `[{name, code}]` |
| Units | `/eleFees/electric/getUnit` | `{"schoolCode", "regCode"}` | `data.datas` → `[{name, code}]` |
| Verify/bind room | `/eleFees/electric/verificationRoom` | `{"cusNo", "type": int, "cusName", "schoolCode", "regCode", "unitCode", "roomNo"}` | `data.status == true` |
| Room info (balances) | `/eleFees/electric/queryRoomInfo` | `{"cusNo", "type", "cusName"}` | `data` → `RoomInfo{type, cusNo, cusName, roomNo, schoolName, regName, unitName, price, balance}` |

`respCode != '00'` → `BalanceQueryException(respDesc ?? fallback message)`.

PayApp-specific auth-expiry detection (in `_decodeResponse`, converted to
`UnauthenticatedException('缴费平台登录状态已失效')` so the retry wrapper re-SSOs):
1. **Redirect to known auth targets**: status 3xx + `Location` resolving (against request URL or base)
   to host `payapp.scu.edu.cn` with path in `{/eleFees/index.html, /eleFees/oauth/airWarrant, /eleFees/oauth/lightWarrant}`.
2. **Login-timeout HTML page**: content-type contains `text/html` OR body (and its malformed-UTF8-decoded
   twin) contains `<html`/`<!doctype html`, AND body contains `登录超时`, AND lowercased body contains
   `/elefees/oauth/airwarrant` or `/elefees/oauth/lightwarrant`.

### 11.4 FitnessApiService

File: `lib/services/api/fitness_api_service.dart`. Depends on: **FitnessAuth**. Base:
`https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php`.

Headers (browser-mimicking, unusual level of fidelity):
```
Accept: application/json, text/plain, */*
Accept-Encoding: gzip, deflate, br, zstd
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6
Cache-Control: no-cache
Connection: keep-alive
Content-Type: application/x-www-form-urlencoded
Origin: https://pead.scu.edu.cn
Pragma: no-cache
Referer: https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php/index/index
User-Agent: <kDefaultUserAgent>
X-Requested-With: XMLHttpRequest
sec-ch-ua: "Microsoft Edge";v="147", "Not.A/Brand";v="8", "Chromium";v="147"
sec-ch-ua-mobile: ?0
sec-ch-ua-platform: "Windows"
```

Endpoints (both POST):
- Notices: `POST $base/index/News/getSchoolNoticeList` (no body) → `data` list → `FitnessNotice`.
- Score: `POST $base/index/Report/getStudentScore` body form `year_num=<year>` → `data` Map →
  `FitnessScore` (null if data not a Map).

Envelope: `{status: "1" ok, info: message, data}`. `_decodeResponse`:
- JSON parse failure → `ServiceException('[<api>] JSON 解析失败')`; non-Map → `ServiceException('[<api>] 响应格式错误')`.
- `status == '1'` → ok.
- Else message = `info ?? '体测服务请求失败'`; if message contains `登录信息失效` OR `请重新登录` →
  `UnauthenticatedException(message)` (triggers re-SSO + one replay); else `ServiceException`.

### 11.5 CcylApiService + CcylService

Files: `lib/services/api/ccyl_api_service.dart` (wrapper with retry), `lib/services/ccyl/ccyl_service.dart`
(stateless HTTP). Depends on: **CcylAuth** (Bearer-like `token` header, not cookies).

CcylService bases:
```dart
static const _base = 'https://dekt.scu.edu.cn';
static const apiBase = 'https://dekt.scu.edu.cn/ccyl-api';
```

Base headers:
```
Accept: application/json, text/plain, */*
Content-Type: application/json;charset=UTF-8
Origin: https://dekt.scu.edu.cn
Referer: https://dekt.scu.edu.cn
User-Agent: <kDefaultUserAgent>
```
Auth headers add `token: <ccyl token>`.

Envelope: `{code: 0 ok, msg, …payload}`; **auth-expiry is HTTP 200 + business `code == 401`**
(`isCcylAuthExpiredCode`) → `CcylAuthExpiredException`. HTTP != 200 → `CcylException('[api] HTTP 错误: <code>')`;
network error → `CcylException('[api] 网络请求失败: …')`.

Endpoints (all POST JSON unless noted; `pn`/`ps` = page num/size; `time` = ms epoch anti-cache):

| Purpose | Path | Body | Payload fields |
|---|---|---|---|
| Login (used by CcylAuth) | `POST $apiBase/app/auth/loginByUc` | `{"code": <oauth code>}` | `token`, `user{id, userName, realname, orgName}` |
| Search activity library | `POST $apiBase/app/activity/list-activity-library` | `{pn, time, ps, name, level, scoreType, org, order, status, quality}` | `list` → `CyclActivity[]` |
| My activities | `POST $apiBase/app/activity/list-mine` | `{pn, time, ps}` | `content` → `CyclActivity[]` |
| Ordered (reserved) activities | `POST $apiBase/app/activity/list-ordered-activity-library` | `{pn, time, ps, name}` | `list` |
| All orgs | `POST $apiBase/app/org/list-all` | `{}` | `list` → `CyclOrg[]` |
| Activity-library detail | `GET $apiBase/app/activity/get-lib-detail/<id>` | — | `activityLib`, `activities[]`, `subscribed` |
| Subscribe library | `POST $apiBase/app/activity/subscribe-act/<id>` | `{}` | code check |
| Cancel subscribe | `POST $apiBase/app/activity/cancel-subscribe/<id>` | `{}` | code check |
| Score types of library | `POST $apiBase/app/activity/list-activity-score/<id>` | `{}` | `list` → `CyclScoreType[]` |
| Sign up | `POST $apiBase/app/activity/sign-up-act` | `{activityId, scoreType}` | code check |
| Cancel sign-up | `POST $apiBase/app/activity/cancel` | `{activityId, userId}` | code check |
| Activity detail | `POST $apiBase/app/activity/get-detail` | `{activityId}` | `activity`, `activityLib?`, `isXtwRole`, `signUp` |
| Credit list | `POST $apiBase/app/credit/list` | `{pn, ps}` | `list` → `CyclCredit[]` |
| Export credits (email PDF) | `POST $apiBase/app/credit/exportPdfV2` | `{creditIds: "<comma-joined>", qqEmail}` | returns `msg` (display string) |
| Dict by group code | `POST $apiBase/app/dict/query-by-group-code` | `{groupCode}` (looped per code) | `list` → `CyclDict[]`; per-code failures swallowed (except auth-expiry which rethrows) |

Wrapper `retryOnCcylAuthError(auth, fn)` (in ccyl_api_service.dart):
```dart
await auth.ensureAuthenticated();
try { return await fn(); }
on CcylAuthExpiredException {
  final ok = await auth.recoverExpiredSession();
  if (!ok) throw UnauthenticatedException('第二课堂 token 过期，重新登录失败');
  return await fn();
}
```
Generic `CcylException` / network errors propagate untouched (protects non-idempotent sign-up/cancel).

### 11.6 ZhhqApiService

File: `lib/services/api/zhhq_api_service.dart` (558 lines). Depends on: **ZhhqAuth**.
Base: `const String _base = 'https://zhhq.scu.edu.cn/api'`.

Per-request Token header — regenerated for EVERY request:
```dart
String _buildToken(String tokenKey) {
  final payload = {
    'tokenKey': tokenKey,
    'clientId': ZhhqCrypto.clientId,          // 'web201911chengdu'
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'GUID': _guid(),                           // v4-style GUID, Random.secure()
  };
  return ZhhqCrypto.encrypt(jsonEncode(payload), key: ZhhqCrypto.clientSecret, iv: ZhhqCrypto.clientId);
}
```
GUID: pattern `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`; `x` nibbles random hex, `y` = `3 & n | 8`.

Request headers `_headers(client, tokenKey, {json})`:
```
Accept: application/json, text/plain, */*
Content-Type: application/x-www-form-urlencoded; charset=UTF-8   (or application/json;charset=utf-8 when json:true)
Origin: https://zhhq.scu.edu.cn
Referer: https://zhhq.scu.edu.cn/ihome/newrepair
User-Agent: <kDefaultUserAgent>
X-Requested-With: XMLHttpRequest
Token: <freshly built AES token>
TokenKey: <tokenKey>
```

Auth acquisition `_executeWithRetry`:
1. **Fast path**: `_auth.getClientFast()` (independent cookie-less client) + persisted tokenKey → run
   `fn`; on `UnauthenticatedException` (token-class errorCode 4010-4017) fall through.
2. **Full path**: `_auth.getClient()` (SCU session + SSO if needed) → `fn`; on Unauthenticated:
   `_auth.invalidate()` → getClient again → fn (one replay).

Response decoding `_decode(body, statusCode)`:
- 302/401/403 or empty body → `UnauthenticatedException()`.
- `zhhqDecodeResponse(body)` (AES decrypt + JSON) — null → log first 100 chars → `ServiceException('zhhq 响应解析失败')`.
- `errorCode` int in [4010, 4017] → `UnauthenticatedException('zhhq 会话已失效')` (token invalid/timeout/signature).
- Business error (`_businessErrorMessage`): error if `status` non-empty and != 'success' OR `errorCode`
  non-empty and != '0' → `ServiceException(message ?? '操作失败')`.

Endpoints (POST unless noted):

| Purpose | Path | Body | Result |
|---|---|---|---|
| Common addresses | `/repair/oneNetPublish/getCommonAddress` | (form, empty) | `data` → `RepairAddress[]` (has `userId`!) |
| Area tree | `/repair/publish/getAreaTree` | — | `data` → `RepairAreaNode[]` |
| Projects by area | `/repair/publish/getProjectByAreaId` | `areaId` | `data` → `RepairProject[]` |
| Bookable dates | `/repair/publish/getBookDate` | — | `data` → `List<String>` |
| Bookable times | `/repair/publish/getBookTime` | `bookDate` | `data` → `List<String>` |
| My tickets (fast "我的动态") | `/manager/activeTemplateData/list` | form: `search` = JSON string of `[{andOr:'and', searchField:'createUser', operator:'=', searchValue:<userId>}, {andOr:'and', searchField:'systemCode', operator:'=', searchValue:'newRepair'}]`, `order` = `createTime desc` | `data` → `RepairTicket.fromDynamicJson[]`; client-side sort by `activeTime` desc (lexicographic `YYYY-MM-DD HH:mm:ss`), fallback `createTime` timestamp |
| Ticket detail | `/repair/repairInfo/get` | `id` (= list row `activeId`) | `data` → `RepairTicketDetail` (status numeric, projectName plain) |
| Withdraw allowed? | `/repair/myRepair/ifAllowWithdrawMyRepair` | `id` | `data` bool / 'true' / '1' |
| Withdraw ticket | `/repair/myRepair/withdrawMyRepair` | `id` | code check |
| Evaluate projects | `/repair/commontProject/getProject` | — | `data` → `[{id, name, weight}]` |
| Submit evaluation | `/repair/visitEvaluateUser/save` | JSON `{common: [<project objects with star 1-5>], content, repairId (from finishedInfo.repairId), source: '0', label: '<comma-joined>'}` | code check |
| Save common address | `/repair/userCommonAddress/save` | JSON `{areaId, areaName ('望江学生区/东苑五栋' style), addressDetail, phone, userName, ifCommon: '1'/'0', id: ''}` | errorCode != '0' → ServiceException |
| Pre-fetch accept dept | `/repair/publish/getAcceptUserByAreaIdAndProjectId` | `areaId, projectId` | `data.dept` else `data.users[0]` → `RepairAcceptDept{deptId, deptName, payName}` (feeds publish's acceptDeptId/acceptDeptName/payName); null-tolerant |
| Submit ticket | `/repair/publish/publish` | JSON payload (assembled by caller with acceptDept fields + `resourcesVOS.fileUrl` from uploads) | errorCode check |
| Upload image | `/api/file/upload` — multipart: field `file` + `system=manager`; **30 s timeout**; response is PLAIN JSON (skips AES) | multipart | `data.path` → used in `resourcesVOS.fileUrl`; 302/401/403 → Unauthenticated; business error via shared `_businessErrorMessage` |

(Note: `oneNetPublish/myList` exists but is deprecated — 20 s+ latency; the code uses `manager/activeTemplateData/list`.)

### 11.7 ServiceApiService (+ dynamic form engine models)

File: `lib/services/api/service_api_service.dart` (529 lines). Depends on: **ServiceAuth**
(CAS cookies `vjuid` etc. auto-attached by CookieClient). Base: `https://service.scu.edu.cn`.

Constants:
```dart
static const String leaveAppId = '350';          // 离校请假
static const String returnReportAppId = '337';   // 返校报备
static const String summerLeaveAppId = '356';    // 暑假离校
static const String stayRegisterAppId = '357';   // 留校登记
static const String kDefaultStarterDepartId = '395876';
static const String tutorDataSourceId = '8';     // DataSource_85 辅导员
static const Map<String, String> paths = {
  'formStartData': '/site/form/start-data',
  'processStartInfo': '/site/process/start-info',
  'processVariables': '/site/process/variables',
  'selectDepartment': '/site/user/select-department',
  'dataSourceDetail': '/site/data-source/detail',
  'attachUpload': '/site/attach/auth-upload',
  'provinceDict': '/api/dictionary/province',
  'formPlugins': '/site/form/get-formv',
  'launch': '/site/apps/launch',
  'instList': '/site/process/inst-list',
};
```

Headers: form-posts use `Content-Type: application/x-www-form-urlencoded` + Origin/Referer = base +
X-Requested-With; JSON gets use `Accept/Content-Type: application/json;charset=UTF-8` + same.

Expiry `_decodeResponse`: 302/401/403 or empty body → Unauthenticated; `e == '10042'` →
`UnauthenticatedException('办事大厅会话已失效')` (vjuid missing/invalid); other `e != '0'` logged to
AuthLogger as `业务错误 e=<e> m=<m> status=<code>`.

| Purpose | Method & Path | Params | Notes |
|---|---|---|---|
| Form schema (auth + prefilled data) | GET `/site/form/start-data?app_id=<>&node_id=&userview=1&agent_uid=&starter_depart_id=<>` | — | `d` → `ServiceFormDefinition{currform:[1419], auth:{"1419":{key:require|writable|readable|front_readonly}}, data:{"1419":{key: value}}}` (currform entries are ints; auth/data keys are Strings) |
| Process start info | GET `/site/process/start-info?app_id=<>` | — | raw `d` (bpmn_id, nodes, form list w/ form_id + version_id — no plugins) |
| Form plugins (primary source) | GET `/site/form/get-formv?id=<formId>&bpmn_id=<>&sess_id=0&report_id=0&agent_uid=&starter_depart_id=<>` | — | `d` = `{id, form_version_id, plugins: "<JSON string>", table}`; plugins decode → `{nowNum, plugins: {key: plugin}, rtplugins}` |
| Starter depart id | GET `/site/user/select-department?app_id=<>` | — | `d.depart[]`, take item with `select == 1`, field `college` (fallback keys: depart_id, department_id, value, id; then first item); null → caller falls back to 395876 |
| Data source value (e.g. tutor) | POST `/site/data-source/detail` (urlencoded) | `id, inst_id=0, app_id, form_version_id, component, params[formId], params[pluginKey], agent_uid='', starter_depart_id, configure[<k>]=<v>…` | `d` map; `d.list` single-value → string, multi-column → object; failure returns null (non-blocking) |
| Province dict | GET `/api/dictionary/province?agent_uid=&starter_depart_id=395876` | — | `d` list (or `d.list`/`d.children`) |
| Attachment upload | POST `/site/attach/auth-upload?category=all&inst_id=0` multipart field `upfile` | Referer: `/v2/matter/start?id=<appId>` | response `{url, size, title, original, state, type, id}` — **no `e` field**; may be double-encoded (JSON string inside JSON) → decode twice if String; ok ⇔ `url != null || state == 'SUCCESS'`, and `id != null`; build download URL `/site/attach/auth-download?file_id=<id>` |
| Submit matter | POST `/site/apps/launch` (urlencoded) | `data=<JSON string {"app_id","node_id":"","form_data":{...},"userview":1}>&step=0&agent_uid=&starter_depart_id=<>` | `e != 0` → `ServiceException(m ?? '提交失败')` |
| My applications | GET `/site/process/inst-list?p=<page>&page_size=20&status=<0|1|3>&keyword=&time_lower=&time_upper=&y=&task_name=` | — | status semantics: 0 = all (server maps to [0,1,2,4,7]), 1 = active+draft ([0,7]), 3 = completed ([4]); rows have actual `status` 2 + `inst_status` Chinese text, `app_name`, `created`. Result `d.list` (or `d` as list) |

Form-engine model files (needed to render the dynamic forms):

- `service_form_models.dart` — `ServiceFormDefinition` (above) with helpers
  `isRequired(key) ⇔ auth[key]=='require'`, `isReadOnly ⇔ readable|front_readonly|readonly`,
  `editableFields`, `prefilledFields`.
- `service_field_type.dart` — `ServiceFieldType` enum: input, multiInput, radio, select, selectV2,
  checkbox, calendar, region, file, dataSource, user, showHide, variate, validate, conversion,
  repeatTable, text, image, table, unknown.
  Resolution: declared plugin `type` (strip leading `d`, lowercase — e.g. `dRadio` → `radio`) against
  `_kComponentTypes`; fallback key prefix map `_kPrefixTypes`:
  `Input_, MultiInput_, MultiText_→multiInput, Radio_, Select_, SelectV2_, Checkbox_, Calendar_,
  Region_, File_, Ximage_→file, DataSource_, User_, ShowHide_, Variate_, Validate_, Conversion_,
  RepeatTable_, Text_→text, Image_, Table_`.
- `service_plugin_models.dart` — `ServiceFormPlugin` (key, type, label from plugin top-level
  `description` — `attr.data.name` is a binding-expression name, fallback only —, sort, options from
  `attr.data.options` `{value,name,default}`, hint from `placeholder`, maxCount from `maxNum` (0/absent → 3;
  NOT `limitval`), `ServiceDataSourceRef` for DataSource plugins (from `attr.data.sourceid/resultKey/
  mapConfig/sourceConfig`; `resultKey == 'setplugin'` = multi-column fan-out mode),
  `ServiceDateOrderRule` for Validate plugins (rule regex
  `^\s*\{f_dateDayMinus\}\(\s*\{p_([A-Za-z0-9_]+)\}\s*,\s*\{p_([A-Za-z0-9_]+)\}\s*\)\s*<\s*0\s*$`
  + `alert` text; A ≤ B legal). `attr` and `attr.data` may be double-encoded JSON strings — decode both.
  `ServiceFormSchema.build` merges get-formv `d` + `ServiceFormDefinition`; `placeholderTypes`
  (showHide/variate/validate/conversion/repeatTable/text/image/table/unknown) submit `''` — except
  conversion/repeatTable/selectV2/checkbox/file submit `[]`; `isSuppressed ⇔ hidden|forbidden`.
- `service_showhide_rule.dart` — `ServiceShowHideRule` (`attr.data.conditions[]` name/expression +
  `controls[]` conkey→`setInfo{isShow, isRequired, isEmpty, plugins[] targets}`); evaluation order:
  all matching conditions' controls applied in order (later overrides). Supported expression forms
  (unsupported → null = not matched; "default true" conditions always parse):
  `true` / `false`; `{p_K}==v` / `!=v`; `{p_K}==''` / `!=''`; `{p_K}.indexOf(v)!==-1` / `==-1`;
  `{p_K}.includes('s')`; `{p_K}[0].value==v` / `{p_K}[0]==v` (+ `!=`);
  `new Date({p_K}) <= new Date('yyyy-MM-dd')` (also `<`, `>`, `>=`); `A||B` disjunctions.
  Date parser tolerates truncated timezone (`2026-08-10T17:10:21+`).
- `service_form_fields.dart` — hardcoded 350 field metadata (fallback when engine parsing fails):
  `Radio_30` 离开校区 (1 望江 / 2 华西 / 3 江安), `Radio_67` 请假事由 (1 实习 / 2 求职 / 3 探亲访友 /
  4 就医 / 5 出差 / 6 回家 / 7 其它), `Calendar_25` 离校时间, `Calendar_26` 返校时间,
  `Region_80` 去往地址 (3-level region + detail, value = admin division code), `MultiInput_40` 事由说明,
  readonly `User_21` 学号 / `User_22` 姓名 / `User_23` 学院 / `User_24` 手机号.

### 11.8 NewServiceApiService

File: `lib/services/api/new_service_api_service.dart`. Depends on: **NewServiceAuth**
(cookies `process_uid`/`process_number`). Base `https://service.scu.edu.cn`, path `/newservice`.
(The frontend maps `site/scuPasspoint*` → `/site/passpoint/*` prefixed with `/newservice`.)

Headers (`_jsonHeaders`): Accept json, X-Requested-With, Origin = base,
Referer = `https://service.scu.edu.cn/newservice/fe/site/m_passpoint`, UA.

Expiry `_decodeResponse`: 302/401/403 or empty body → Unauthenticated; `looksLikeLoginPage(body)` →
Unauthenticated; `e != 'OK'` → if `e == 'UN_AUTH'` → `UnauthenticatedException('newservice 登录已失效')`
else `ServiceException(m ?? '服务暂不可用')`.
Inner business check `_checkData(d)`: `d.errorCode != 0` → `ServiceException(d.errorMessage ?? '操作失败')`
(logged as `NEWSERVICE`).

Endpoints:

| Purpose | Method & Path | Params | Result |
|---|---|---|---|
| MAB devices | GET `/newservice/site/passpoint/query-user-mab-info?limit=100` | — | `d.data` → `PasspointDevice[]` |
| Account info | GET `/newservice/site/passpoint/query-user` | — | `d.queryUserResult.data` → `PasspointUserInfo?` |
| Add device | POST `/newservice/site/passpoint/add-user-mab-info` | form: `userMac`, `macExpireTime` (0-365 days; 0 = max ~6 years), `defaultServiceName` ('' = campus exit; or ISP name e.g. 中国电信) | errorCode check |
| Cancel device | POST `/newservice/site/passpoint/cancel-user-mab-info` | form: `userMac`, optional `userId` | errorCode check |

### 11.9 AcademicCalendarService

File: `lib/services/api/academic_calendar_service.dart`. **No auth** — public GitHub-hosted JSON.

URLs:
```dart
static const String _remoteUrl =
    'https://raw.githubusercontent.com/The-Brotherhood-of-SCU/Bugaoshan/main/assets/academic_calendar.json';
static const String _mirrorUrl =
    'https://gh-proxy.com/https://raw.githubusercontent.com/The-Brotherhood-of-SCU/Bugaoshan/refs/heads/main/assets/academic_calendar.json';
static const String _cacheKey = 'cached_academic_calendar_json'; // SharedPreferences
```

Behavior: local-first (prefs cache → bundled asset `assets/academic_calendar.json`); network only on
first install; pull-to-refresh tries mirror then remote (5 s timeout); empty `semesters` responses are
NOT cached (pollution guard). Compact JSON format expansion (`expandCalendarJson`): top-level
`eventTypes: {key: {l: label, t: tag}}`; each semester `{n: name, s: startDate, w: totalWeeks,
e: {typeKey: "date" | ["start","end"]}}` → expanded `{name, startDate, totalWeeks, events: [{label,
tag, date, endDate?}]}`. Semester matching for week counts: regex `(\d{4})-(\d{4})` from schedule
name + contains `春`/`秋`. Also generates ICS exports (VTIMEZONE Asia/Shanghai etc.).

### 11.10 ForgotPasswordService

File: `lib/services/api/forgot_password_service.dart`. No login state required.

Constants:
```dart
static const _base = 'https://id.scu.edu.cn';
static const _enterpriseId = 'scdx';
static const _captchaPath = '/api/public/bff/v1.2/one_time_login/captcha';
static const _apiPrefix = '/api/public/bff/v1.2/forgot_password';
```
Headers identical to ScuAuth's default set (Origin/Referer = id.scu.edu.cn/frontend/login).

Three-step flow (each POST body is JSON, URL also carries `?_enterprise_id=scdx`):

| Step | Endpoint | Body |
|---|---|---|
| Captcha | GET `$_captchaPath?_enterprise_id=scdx&time=<ms>` (note: param name here is `time`, not `timestamp`) | — |
| 1. Verify user | POST `/api/public/bff/v1.2/forgot_password/verify_user` | `{_enterprise_id, username, phoneRegion: '', captcha: <text>, captchaCode: <code>}` → `data {phone, email, sToken}` (raw values — mask before display: phone `123****7890` keep 3+4; email keep 2 local chars + domain) |
| 2a. Send code | POST `…/forgot_password/obtain_code` | `{_enterprise_id, username, type: 'phone'|'email', sToken}` |
| 2b. Verify code | POST `…/forgot_password/verify_code` | `{_enterprise_id, username, type, code, sToken}` → `data.token` (reset token) |
| 3. New password | POST `…/forgot_password/submit` | `{_enterprise_id, token, password (PLAINTEXT JSON over HTTPS — no SM2), rePassword (= password), phone|email: username}` |

Response convention mix: gateway failures `{"code": 4xx, "message"}`; login-style `success` flag —
`_parseResponse` accepts ok ⇔ `success == true` (when key present) OR `code` null/200/'200'.
Errors: `ForgotPasswordException(message, businessCode)`; message keys tried in order
`message, msg, error_description`. Known business codes: 400 wrong captcha, 439 expired captcha.

---

## 12. ZhhqCrypto — exact algorithm + keys

File: `lib/utils/zhhq_crypto.dart`. Front-end-verified against zhhq webpack module 7b7e.

```dart
static const String _responseKey = '1974051005060708';  // 16 ASCII chars = 128-bit key
static const String _responseIv  = '1974051005060708';  // same value as IV
static const String clientId     = 'web201911chengdu';  // 16 chars — used as IV for Token encryption
static const String clientSecret = 'bf8ec0449942e7f4';  // 16 chars — used as KEY for Token encryption
```

- Algorithm: **AES-128-CBC, PKCS7 padding** (encrypt package's default for CBC).
- `encrypt(plaintext, {key, iv})`: key = `key ?? '1974051005060708'` (UTF-8 bytes), iv likewise; output
  **base64** ciphertext.
- `decrypt(ciphertextBase64, {key, iv})`: same params, returns UTF-8 plaintext.
- Usage matrix:
  - Response-body decryption: default key AND default IV (`1974051005060708` / `1974051005060708`).
  - `Token` request header + login/auto `timestamp` field: key = `clientSecret` (`bf8ec0449942e7f4`),
    iv = `clientId` (`web201911chengdu`).
- `zhhqDecodeResponse(body)`: `decrypt(body)` → `jsonDecode` → Map; any failure → null.
- Security note (from source comments): `clientSecret` is a public front-end constant (extractable from
  the zhhq JS bundle), not a real secret — do not rotate, do not treat as a credential, do not redact in
  logs.

Swift: `CryptoKit` has no CBC — use `CommonCrypto` (`CCCrypt` with `kCCAlgorithmAES`, `kCCOptionPKCS7Padding`)
or `Crypto`/SwiftCrypto AES-GCM is NOT compatible. Keys/IVs are the raw 16 ASCII bytes.

---

## 13. SM2Crypto — login password encryption

File: `lib/utils/sm2_crypto.dart` (uses `dart_sm` package).

`encryptWithBase64Key(plaintext, publicKeyBase64)`:
1. base64-decode the server public key.
2. If first byte != `0x04`, prepend `0x04` (uncompressed point marker).
3. Hex-encode the 65 bytes (130 hex chars) — dart_sm wants `04||x||y`.
4. `SM2.encrypt(plaintext, pubKeyHex, cipherMode: C1C2C3)` (dart_sm default is C1C3C2 — must override).
5. dart_sm outputs hex of `C1(128 hex, no 04) + C2 + C3`; prepend byte `0x04` again, base64-encode
   everything → final `04 || C1 || C2 || C3` base64 string sent as the `password` field.

Swift port: no first-party SM2 in CryptoKit. Options: bundle a C/ObjC SM2 implementation, a Swift
wrapper over GMSSL/BouncyCastle-style code, or a tiny Rust/`swift-crypto`-style bridged crate. The
exact wire format (C1C2C3 with leading 04, base64) and the SM2 standard curve (sm2p256v1) are the
contract. The public key comes fresh from `sm2_key` each login.

---

## 14. Storage Keys Catalog

File: `lib/utils/storage_keys.dart` + private consts elsewhere.

### FlutterSecureStorage (→ iOS Keychain)

Config (`lib/utils/secure_storage.dart`): `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`
— Swift: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

| Key | Written by | Purpose |
|---|---|---|
| `scu_access_token` (`kScuAccessToken`) | ScuAuth.login | SCU unified-auth access token (root credential) |
| `scu_principal_binding_v1` (`kScuPrincipalBinding`) | ScuAuth.login | JSON `{"principal": <username>, "tokenFingerprint": <sha256hex(token)>}` — principal restored only when fingerprint matches current token |
| `scu_saved_username` (`kScuSavedUsername`) | ScuAuth.saveCredentials | Saved username for auto-login (also read by login_status_card.dart) |
| `scu_saved_password` (`kScuSavedPassword`) | ScuAuth.saveCredentials | Saved password (plaintext in secure storage) for auto-login |
| `scu_remember_password` (`kScuRememberPassword`) | saveCredentials/clearCredentials | `'true'` flag gating getSavedCredentials |
| `scu_auto_login` (`kScuAutoLogin`) | ScuAuthProvider.setAutoLogin | `'true'`/`'false'` — UI-level auto-login switch (checked before ScuAuth.autoLogin in provider path) |
| `zhhq_token_key` (`kZhhqTokenKey`) | ZhhqAuth | zhhq tokenKey (`ITSOFT-WILAB-SESSION` value); deleted on invalidate/SCU logout |
| `ccyl_session_v2` (private in ccyl_auth.dart) | CcylAuth | JSON `{"token", "userId", "scuPrincipal"}` |
| `ccyl_token` (legacy) | — | deleted on CcylAuth.init (migration cleanup) |
| `ccyl_user_id` (legacy) | — | deleted on CcylAuth.init + on commit (kept clean) |

### SharedPreferences (→ UserDefaults)

| Key | Purpose |
|---|---|
| `scu_login_timestamp` (`kScuLoginTimestamp`) | int, unix seconds of last successful login/bind — drives the 1-hour TTL |
| `scu_user_realname` (`kScuUserRealname`) | cached display name (from wfw profile `d.base.realname`) |
| `scu_user_number` (`kScuUserNumber`) | cached student id (from wfw profile `d.base.role.number`) |
| `cached_academic_calendar_json` | raw academic calendar JSON cache (academic_calendar_service) |

(Swift port note: keys 1-3 are the only auth-related UserDefaults entries; everything credential-ish
stays in Keychain.)

---

## 15. UserInfo — where name / student id come from

Files: `lib/providers/user_info_provider.dart` (288 lines), `lib/providers/scu_auth_provider.dart`.

Source of truth: **WfwApiService** on the wfw (微服务) backend:

- `fetchUserProfile()` → GET `https://wfw.scu.edu.cn/uc/wap/user/get-info` → `d.base` map:
  - `realname` → display name
  - `role.number` → student/staff number (`role` is a Map)
  - full profile also kept in memory (`_profile`) for department/contact fields (deep-frozen on read).
- `fetchProfileLabels()` → GET `https://wfw.scu.edu.cn/mashupapp/wap/real/user` → `d.labels` list.

`UserInfoProvider` trigger chain:
- Listens to `WfwAuth`. On **edge** `unknown→ready` only (level-triggered would loop: invalidate →
  warm-up → ready → fetch → fail → invalidate …) schedules `_fetchAll` after **300 ms** delay
  (to avoid colliding with PayApp SSO chains still using the same CookieClient); constructor also does
  an immediate check (`Duration.zero`) for the DI-restore case.
- `_fetchAll(generation)`: request-generation guarded; parallel `fetchUserProfile` + `fetchProfileLabels`;
  on `UnauthenticatedException` → error state; other errors → one retry after 1 s.
- `_applyResult`: sets `_labels`, `_profile`, `_userRealname`, `_userNumber`; calls
  `ScuAuthProvider.setUserInfo(realname, number)` (back-compat) and enqueues **serialized**
  persistence (`_persistenceTail` chain) writing `kScuUserRealname` / `kScuUserNumber` to
  SharedPreferences (null → remove).
- On wfw `unknown` (logout) → `clear()` (bumps generation, nulls everything, persists nulls).
- `retry()`: if wfw ready → refetch; else `ensureAuthenticated()` then refetch (covers the silent
  rebuild case where no new ready edge fires).

`ScuAuthProvider.init()` loads the two cached strings for immediate display after cold start;
`logout()` removes them.

---

## 16. AuthLogger

File: `lib/utils/auth_logger.dart` (266 lines). GetIt singleton; `ChangeNotifier`.

- Ring buffer, default capacity **1000** entries `AuthLogEntry{timestamp, level, tag, message}`.
- Line format: `HH:mm:ss.SSS LEVEL [tag] message` (`padRight(5)` level; with date:
  `yyyy-MM-dd HH:mm:ss.SSS`).
- **Redaction before any write** (`AuthLogRedactor.apply`):
  - `("access_token"\s*:\s*)"[^"]*"` → `<redacted>` (same for `"password"`)
  - `Bearer\s+[A-Za-z0-9._\-]+` → `Bearer <redacted>`
  - `([?&](?:code|access_token)=)([^&\s"]+)` → keep first 4 chars + `…` (or full redact if ≤4)
  - `\b(user(?:name|id)?|student(?:id|number)?|number)\s*=\s*([^\s,;]+)` → `<redacted>`
  - `("(?:username|userId|studentId|studentNumber|number)"\s*:\s*)"[^"]*"` → `<redacted>`
- Console only in debug builds (`debugPrint`); optional file sink `auth.log` in app documents
  (append, no rotation); export writes `bugaoshan-auth-<yyyyMMdd-HHmmss>.log`.
- Tags used across the codebase (for grep parity): `ScuAuth`, `CookieClient`, `AuthCoordinator`,
  `ZhjwAuth`, `WfwAuth`, `PAYAPP`/`FITNESS`/`SERVICE`/`NEWSERVICE` (moduleId.toUpperCase()),
  `CcylAuth`, `CcylOAuth`, `ZHhq` (sic — mixed case for zhhq), `ScuAuthProvider`.

---

## 17. JSON Utils

File: `lib/utils/json_utils.dart` — `parseJson(body, api, exceptionFactory)` /
`parseJsonList(...)`: safe decode, ≤200-char preview debug log, exception via factory
(`'[<api>] 响应解析失败'`). Lenient accessors `safeDouble/safeInt/safeString/safeBool` (see §11.0)
— port these as `JSONValue` helpers in Swift to survive the wildly inconsistent server typing
(ints as strings, bools as '1'/'true', nulls everywhere).

---

## 18. DI / Lifecycle Wiring

From `docs/architecture/authentication.md` §13 (injector.dart registration order):

```
SharedPreferences → ScuAuth.init
ScuAuth → ZhjwAuth / WfwAuth / FitnessAuth / CcylAuth(.init) / PayAppAuth(deps: wfw)
[zhjw, wfw, payapp, fitness, ccyl] → AuthCoordinator
auths → API services (Zhjw/Wfw/PayApp/Ccyl/…)
ScuAuth + CcylAuth + AuthCoordinator → ScuAuthProvider
WfwAuth + WfwApiService → UserInfoProvider
```

Logout orchestration (`ScuAuthProvider.logout()`):
1. `ScuAuth.logout()` (epoch++, wipe root state),
2. `CcylAuth.logout()`,
3. `AuthCoordinator.invalidateAll()` (all L2 invalidate),
4. remove `kScuUserRealname`/`kScuUserNumber` prefs,
5. root-state listeners clear downstream provider caches (PlanCompletion, UserInfo, …).

Warm-up entry points: `ScuAuthProvider.login()` (unawaited warmUpAll) and home-page cold-start
auto-login success.

---

## 19. Swift Porting Notes (gotchas checklist)

1. **zhjw is plain HTTP** — ATS exception for `http://zhjw.scu.edu.cn` (NSAppTransportSecurity
   exception domain) is mandatory or every jwxt request fails.
2. **Manual redirect control is load-bearing.** `URLSession` follows redirects by default and does NOT
   let you intercept per-hop cookies+headers the way this app needs (per-hop cookie domains, Bearer
   stripping on cross-origin). Implement `willPerformHTTPRedirection` → cancel → re-issue via the
   CookieClient equivalent. Max 10 hops.
3. **Bearer header leak protection**: only forward `Authorization` when the hop is same-origin with the
   initial URL (or explicitly allow-listed). Every SSO entry (zhjw jwt23, zhhq jwt31, payapp, fitness,
   service, newservice, ccyl sp_logged) starts with Bearer on id.scu.edu.cn then crosses origins.
4. **Single-flight everywhere**: root bind, root refresh, coordinator warm-up, each subsystem login,
   CCYL reLogin — all coalesce concurrent callers. In Swift use `actor` + stored `Task` checked on
   completion identity (`if identical` → compare via stored reference/generation int).
5. **Epoch/generation discipline**: ScuAuth `_authEpoch`, CcylAuth `_authGeneration` — capture at task
   start, compare before *every* commit point (memory + storage). Logout must complete pending
   refresh completers with `false` so waiters don't hang.
6. **WFW readiness trap**: never use the homepage or status-code/cookie-presence as the ready signal —
   only `get-info` returning JSON `e == 0`. Anonymous `eai-sess` sessions otherwise cause an infinite
   invalidate loop.
7. **Login-page detection** is HTML-only + strong-feature based (title / j_spring_security_check form /
   meta-refresh / JS-location / form-action, all gated by `\blogin\b`); JSON never matches. Port the
   exact regexes from §10.2 (issue #282 regression).
8. **The wfw envelope `e`** appears as both int and string depending on endpoint era — always compare
   both. Codes: `0` ok, `10013` auth-expired (wfw), `10042` auth-expired (service), `'OK'` ok /
   `'UN_AUTH'` expired (newservice), `401` business-code = CCYL token expired, zhhq `errorCode`
   4010-4017 = token class.
9. **zhhq double crypto**: request `Token` header is AES(key=clientSecret, iv=clientId) over a JSON
   blob containing the tokenKey; response bodies are AES(default key/iv) base64 — except
   `/api/file/upload` which is plaintext JSON. `timestamp` field in login/auto is AES'd with the
   DEFAULT key/iv.
10. **SM2**: C1C2C3 mode, 04-prefixed, base64 — not the more common C1C3C2. Needs a third-party/crypto
    port; the public key is ephemeral per login.
11. **Set-Cookie splitting**: multiple cookies arrive comma-joined; the split regex
    `,\s*(?=[A-Za-z][^,=\s]*\s*=)` avoids cutting on expires-date commas.
12. **Reusable-client close semantics**: `close()` no-ops for the cached root client; logout uses
    `closeForce()`. In Swift, model as explicit `invalidate()` on the session.
13. **Cookie-domain matching** is suffix-based (`host == jarHost || host.endsWith('.jarHost'))`, not
    RFC 6265 path-aware; no expiry/secure/httponly tracking. Replicate simple behavior, don't
    "improve" it with HTTPCookieStorage unless per-client isolation is preserved (multiple subsystem
    SSO chains share ONE client per login generation by design).
14. **zhjw rate limiting**: `请勿频繁刷新` in body → RateLimitedException; keep the 600 ms
    `planDetailRequestGap` between plan detail fetches.
15. **Attr double-encoding** in the service form engine: `attr` and `attr.data` may each be JSON
    strings; decode both defensively. Upload responses may also be double-encoded JSON strings.
16. **`scu_login_timestamp` is seconds**, not ms (`millisecondsSinceEpoch ~/ 1000`), while captcha
    `timestamp`, CCYL `time`, zhhq `timestamp` are ms. Don't unify blindly.
17. **Forgot-password captcha query param** is `time=` (not `timestamp=`) — differing from login's
    `timestamp=`.
18. **newservice redirect_url** contains `platform_id=31` twice (encoded) — intentional, keep verbatim.
19. **OCR dependency** is a bundled native model (`scu_ocr_lite` plugin + `model.scuocr` asset);
    auto-login quality depends on it. Plan an iOS equivalent (Vision/CoreML or the same model).
20. **Logout has no server-side calls** — all sessions die by cookie/token discard server-side
    eventually; nothing to POST.
