(() => {
  if (window.__betterOqbDataBridgeInstalled) return;
  window.__betterOqbDataBridgeInstalled = true;

  const MAX_PAYLOAD = 600000;
  const allowed = new Set([
    '/api/get_usable_packages',
    '/api/load_papers',
    '/api/load_submitted_papers',
    '/api/get_user_question_stat',
    '/api/search_questions',
    '/api/start_trial',
    '/api/load_paper',
    '/api/save_trial',
    '/api/save_paper',
  ]);

  function pathOf(rawUrl) {
    try {
      return new URL(rawUrl, location.href).pathname;
    } catch (_) {
      return '';
    }
  }

  function relevant(rawUrl) {
    return allowed.has(pathOf(rawUrl));
  }

  function safeString(value) {
    const text = String(value);
    if (/^https?:\\/\\//i.test(text)) {
      try {
        const parsed = new URL(text);
        if (parsed.searchParams.has('sig')) parsed.searchParams.set('sig', '[redacted]');
        if (parsed.searchParams.has('token')) parsed.searchParams.set('token', '[redacted]');
        if (parsed.searchParams.has('sesskey')) parsed.searchParams.set('sesskey', '[redacted]');
        return parsed.href;
      } catch (_) {}
    }

    return text
      .replace(/([?&](?:sig|token|sesskey)=)[^&]+/gi, '$1[redacted]')
      .replace(/((?:token|sesskey|password)\\s*[:=]\\s*)[^&\\s,;]+/gi, '$1[redacted]');
  }

  function sanitize(value, depth = 0) {
    if (depth > 14) return null;

    if (Array.isArray(value)) {
      return value.slice(0, 1000).map((item) => sanitize(item, depth + 1));
    }

    if (value && typeof value === 'object') {
      const out = {};
      for (const [key, item] of Object.entries(value)) {
        if (/^(token|sesskey|user_info|owner_id|external_id|city_id|cfullname|efullname|nickname)$/i.test(key)) {
          continue;
        }
        out[key] = sanitize(item, depth + 1);
      }
      return out;
    }

    if (typeof value === 'string') return safeString(value);
    return value;
  }

  function safeBody(body) {
    if (body == null) return '';
    const raw = typeof body === 'string'
      ? body
      : body instanceof URLSearchParams
        ? body.toString()
        : '';
    if (!raw) return '';
    return raw
      .replace(/(^|&)(token|sesskey|password)=[^&]*/gi, '$1$2=[redacted]')
      .slice(0, 12000);
  }

  function emit(rawUrl, method, requestBody, payload) {
    if (!relevant(rawUrl)) return;

    const event = {
      timestamp: new Date().toISOString(),
      url: rawUrl,
      path: pathOf(rawUrl),
      method: String(method || 'GET').toUpperCase(),
      requestBody: safeBody(requestBody),
      response: sanitize(payload),
    };

    let encoded;
    try {
      encoded = JSON.stringify(event);
    } catch (_) {
      return;
    }
    if (encoded.length > MAX_PAYLOAD) return;

    try {
      if (window.flutter_inappwebview?.callHandler) {
        window.flutter_inappwebview.callHandler('betterOqbApiData', encoded);
      } else if (window.BetterOqbData?.postMessage) {
        window.BetterOqbData.postMessage(encoded);
      }
    } catch (_) {}
  }

  const previousFetch = window.fetch?.bind(window);
  if (previousFetch) {
    window.fetch = async function(input, init = {}) {
      const request = input instanceof Request ? input : null;
      const url = request?.url || String(input);
      const method = init.method || request?.method || 'GET';
      const body = init.body;
      const response = await previousFetch(input, init);

      if (relevant(url)) {
        try {
          const text = await response.clone().text();
          const payload = JSON.parse(text);
          emit(url, method, body, payload);
        } catch (_) {}
      }

      return response;
    };
  }

  const XHR = window.XMLHttpRequest;
  if (XHR?.prototype) {
    const previousOpen = XHR.prototype.open;
    const previousSend = XHR.prototype.send;

    XHR.prototype.open = function(method, url, ...rest) {
      this.__betterOqbDataMethod = method || 'GET';
      this.__betterOqbDataUrl = String(url);
      return previousOpen.call(this, method, url, ...rest);
    };

    XHR.prototype.send = function(body) {
      this.__betterOqbDataBody = body;
      this.addEventListener('loadend', () => {
        const url = this.__betterOqbDataUrl || '';
        if (!relevant(url)) return;

        try {
          let payload;
          if (this.responseType === 'json') {
            payload = this.response;
          } else if (this.responseType === '' || this.responseType === 'text') {
            payload = JSON.parse(this.responseText);
          } else {
            return;
          }
          emit(
            url,
            this.__betterOqbDataMethod || 'GET',
            this.__betterOqbDataBody,
            payload,
          );
        } catch (_) {}
      }, { once: true });

      return previousSend.call(this, body);
    };
  }
})();
