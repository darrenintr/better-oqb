// Better OQB same-origin API client.
//
// Runs inside the authenticated oqb.edcity.hk WebView. It is the ONLY place
// that touches the OQB authentication token and trial sesskeys:
//
// - The token is learned from OQB's own API requests (forwarded by
//   oqb_data_bridge.js) and kept in this closure. It is never sent to Flutter.
// - Trial sesskeys are learned from start_trial responses and kept in this
//   closure, keyed by trial id. They are never sent to Flutter.
// - Requests are only sent to relative /api/ paths on the current origin, and
//   only when that origin is oqb.edcity.hk.
//
// Flutter calls window.betterOqbApi.run(requestId, command, fields). Endpoint
// field layouts are built (and unit tested) on the Dart side; this file only
// adds app/token/sesskey and posts the form.
(() => {
  if (window.betterOqbApi) return;

  const OQB_HOST = 'oqb.edcity.hk';
  const MAX_RESULT = 25 * 1024 * 1024;
  const MAX_ASSET = 10 * 1024 * 1024;
  const pageInstance = Math.random().toString(36).slice(2);

  // command -> endpoint description. Anything not listed is refused.
  const COMMANDS = {
    getMeta: { path: '/public/meta.json', method: 'GET', auth: false },
    getUserMeta: { path: '/api/get_user_meta' },
    getUsablePackages: { path: '/api/get_usable_packages' },
    loadPapers: { path: '/api/load_papers' },
    loadSubmittedPapers: { path: '/api/load_submitted_papers' },
    getUserQuestionStat: { path: '/api/get_user_question_stat' },
    searchQuestions: { path: '/api/search_questions' },
    loadPaper: { path: '/api/load_paper' },
    startTrial: { path: '/api/start_trial', capturesSesskey: true },
    saveTrial: { path: '/api/save_trial', needsSesskey: true, submit: '0' },
    submitTrial: { path: '/api/save_trial', needsSesskey: true, submit: '1' },
  };

  const session = {
    token: '',
    tokenSource: '',
    sesskeys: new Map(),
  };

  const nativeFetch = window.fetch ? window.fetch.bind(window) : null;

  function onOqb() {
    return location.host === OQB_HOST;
  }

  function post(message) {
    let encoded;
    try {
      encoded = JSON.stringify(message);
    } catch (_) {
      encoded = JSON.stringify({
        type: 'result',
        id: message && message.id,
        ok: false,
        error: { code: 'encode_failed', message: 'Could not encode result' },
      });
    }
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('betterOqbApi', encoded);
      } else if (window.BetterOqbApi && window.BetterOqbApi.postMessage) {
        window.BetterOqbApi.postMessage(encoded);
      }
    } catch (_) {}
  }

  function status() {
    if (!session.token) discoverStoredToken();
    return {
      type: 'status',
      pageInstance,
      onOqb: onOqb(),
      path: location.pathname,
      hasToken: Boolean(session.token),
      tokenSource: session.tokenSource,
    };
  }

  let lastStatusKey = '';
  function reportStatus(force) {
    const current = status();
    const key = [current.onOqb, current.path, current.hasToken, current.tokenSource].join('|');
    if (!force && key === lastStatusKey) return;
    lastStatusKey = key;
    post(current);
  }

  // ---- learning the session from OQB's own traffic -----------------------

  function fieldFromBody(body, name) {
    if (body == null) return '';
    try {
      if (typeof body === 'string') {
        const trimmed = body.trim();
        if (trimmed.startsWith('{')) {
          const parsed = JSON.parse(trimmed);
          return parsed && typeof parsed[name] === 'string' ? parsed[name] : '';
        }
        return new URLSearchParams(body).get(name) || '';
      }
      if (body instanceof URLSearchParams || body instanceof FormData) {
        const value = body.get(name);
        return typeof value === 'string' ? value : '';
      }
    } catch (_) {}
    return '';
  }

  function plausibleToken(value) {
    return typeof value === 'string' &&
      value.length >= 8 &&
      value.length <= 4096 &&
      !/\s/.test(value) &&
      value !== '[redacted]';
  }

  function rememberSesskey(payload) {
    const trial = payload && payload.result && payload.result.trial;
    if (!trial || trial.id == null) return;
    if (typeof trial.sesskey === 'string' && trial.sesskey) {
      session.sesskeys.set(String(trial.id), trial.sesskey);
    }
  }

  // Called by oqb_data_bridge.js for every same-origin /api/ request OQB makes.
  const observer = {
    request(path, body) {
      if (!onOqb() || !String(path).startsWith('/api/')) return;
      const token = fieldFromBody(body, 'token');
      if (plausibleToken(token) && token !== session.token) {
        session.token = token;
        session.tokenSource = 'request';
        reportStatus(false);
      }
    },
    response(path, payload) {
      if (path === '/api/start_trial') rememberSesskey(payload);
    },
  };
  Object.freeze(observer);
  Object.defineProperty(window, '__betterOqbSessionObserver', {
    value: observer,
    writable: false,
    configurable: false,
    enumerable: false,
  });

  // Fallback only: if OQB has not made an API request on this page yet, look
  // for an obviously named token in web storage. The value stays here.
  function discoverStoredToken() {
    if (session.tokenSource === 'request' || !onOqb()) return;
    for (const store of [window.localStorage, window.sessionStorage]) {
      try {
        for (let i = 0; store && i < store.length; i++) {
          const key = store.key(i);
          if (!/token/i.test(key || '')) continue;
          const raw = store.getItem(key);
          let candidate = raw;
          try {
            const parsed = JSON.parse(raw);
            if (typeof parsed === 'string') candidate = parsed;
            else if (parsed && typeof parsed.token === 'string') candidate = parsed.token;
          } catch (_) {}
          if (plausibleToken(candidate)) {
            session.token = candidate;
            session.tokenSource = 'storage';
            return;
          }
        }
      } catch (_) {}
    }
  }

  // ---- outgoing requests ---------------------------------------------------

  function sanitize(value, depth) {
    if (depth > 24) return null;
    if (Array.isArray(value)) return value.map((item) => sanitize(item, depth + 1));
    if (value && typeof value === 'object') {
      const out = {};
      for (const key of Object.keys(value)) {
        if (/^(token|sesskey|password|user_info|owner_id|external_id|city_id|cfullname|efullname|nickname)$/i.test(key)) {
          continue;
        }
        out[key] = sanitize(value[key], depth + 1);
      }
      return out;
    }
    return value;
  }

  function fail(id, code, message, extra) {
    post(Object.assign({ type: 'result', id, ok: false, error: { code, message } }, extra || {}));
  }

  async function run(id, command, fields) {
    const spec = COMMANDS[command];
    if (!spec) return fail(id, 'unknown_command', 'Command is not allowed: ' + command);
    if (!onOqb()) return fail(id, 'not_on_oqb', 'The browser is not on ' + OQB_HOST);
    if (!nativeFetch) return fail(id, 'no_fetch', 'fetch() is unavailable');

    const started = Date.now();
    let response;
    try {
      if (spec.method === 'GET') {
        response = await nativeFetch(spec.path, { credentials: 'same-origin' });
      } else {
        if (!session.token) discoverStoredToken();
        if (spec.auth !== false && !session.token) {
          return fail(id, 'not_authenticated', 'No OQB session token has been seen yet');
        }

        const form = new URLSearchParams();
        form.set('app', 'OQB');
        form.set('token', session.token);
        if (spec.needsSesskey) {
          const trialId = String((fields && fields.trial_id) || '');
          const sesskey = session.sesskeys.get(trialId);
          if (!sesskey) {
            return fail(id, 'missing_sesskey', 'No sesskey for trial ' + trialId + '; restart the trial');
          }
          form.set('trial_id', trialId);
          form.set('sesskey', sesskey);
        }
        for (const key of Object.keys(fields || {})) {
          if (/^(app|token|sesskey|trial_id|opts\[submit\])$/.test(key)) continue;
          const value = fields[key];
          form.append(key, value == null ? '' : String(value));
        }
        if (spec.submit != null) form.set('opts[submit]', spec.submit);

        response = await nativeFetch(spec.path, {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
          body: form.toString(),
        });
      }
    } catch (error) {
      return fail(id, 'network', String((error && error.message) || error));
    }

    const httpStatus = response.status;
    let text;
    try {
      text = await response.text();
    } catch (error) {
      return fail(id, 'read_failed', String((error && error.message) || error), { httpStatus });
    }
    if (text.length > MAX_RESULT) {
      return fail(id, 'too_large', 'Response exceeded ' + MAX_RESULT + ' characters', { httpStatus });
    }

    let payload;
    try {
      payload = JSON.parse(text);
    } catch (_) {
      return fail(id, 'not_json', 'OQB returned a non-JSON response', { httpStatus });
    }

    if (spec.capturesSesskey) rememberSesskey(payload);

    post({
      type: 'result',
      id,
      ok: response.ok,
      httpStatus,
      elapsedMs: Date.now() - started,
      data: sanitize(payload, 0),
    });
  }

  // Loads an image through the browser (with OQB cookies for same-origin URLs
  // only) and returns it as a data URL. Used when Flutter cannot load a
  // question asset directly. The result is used for rendering and discarded.
  async function fetchAsset(id, rawUrl) {
    if (!nativeFetch) return fail(id, 'no_fetch', 'fetch() is unavailable');
    let url;
    try {
      url = new URL(String(rawUrl), location.href);
    } catch (_) {
      return fail(id, 'bad_url', 'Invalid asset URL');
    }
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      return fail(id, 'bad_url', 'Unsupported asset URL');
    }
    try {
      const response = await nativeFetch(url.href, {
        credentials: url.host === location.host ? 'same-origin' : 'omit',
      });
      if (!response.ok) return fail(id, 'http', 'Asset request failed', { httpStatus: response.status });
      const blob = await response.blob();
      if (blob.size > MAX_ASSET) return fail(id, 'too_large', 'Asset too large');
      const dataUrl = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
      });
      post({ type: 'result', id, ok: true, data: { dataUrl } });
    } catch (error) {
      fail(id, 'network', String((error && error.message) || error));
    }
  }

  function navigate(path) {
    if (typeof path !== 'string' || !path.startsWith('/') || path.startsWith('//')) return false;
    if (!onOqb()) return false;
    location.assign(path);
    return true;
  }

  const api = {
    run(id, command, fields) {
      run(id, command, fields).catch((error) =>
        fail(id, 'internal', String((error && error.message) || error)));
      return true;
    },
    fetchAsset(id, url) {
      fetchAsset(id, url);
      return true;
    },
    reportStatus() {
      reportStatus(true);
      return true;
    },
    navigate,
    commands: Object.keys(COMMANDS),
  };
  Object.freeze(api);
  Object.defineProperty(window, 'betterOqbApi', {
    value: api,
    writable: false,
    configurable: false,
    enumerable: false,
  });

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    if (typeof original !== 'function') continue;
    history[method] = function(...args) {
      const result = original.apply(this, args);
      setTimeout(() => reportStatus(false), 0);
      return result;
    };
  }
  addEventListener('popstate', () => reportStatus(false));
  addEventListener('flutterInAppWebViewPlatformReady', () => reportStatus(true));
  addEventListener('load', () => reportStatus(true));
})();
