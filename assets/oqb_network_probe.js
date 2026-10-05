(() => {
  if (window.__betterOqbNetworkProbeInstalled) return;
  window.__betterOqbNetworkProbeInstalled = true;

  const MAX_EVENTS = 500;
  const MAX_PREVIEW = 8192;
  const SECRET_KEY = /(^|_)(authorization|cookie|csrf|xsrf|token|secret|password|passwd|session|sessionid|sesskey|sid|user_id|city_id|cfullname|efullname|nickname|email_address_hash|register_email_hash|login_email_hash|ip)($|_)/i;
  const buffer = window.__betterOqbNetworkBuffer =
    window.__betterOqbNetworkBuffer || [];

  const now = () => new Date().toISOString();

  function isRelevantUrl(rawUrl) {
    try {
      const url = new URL(rawUrl, location.href);
      if (url.host !== 'oqb.edcity.hk') return false;
      if (url.pathname === '/api/get_teachers') return false;
      return url.pathname.startsWith('/api/') ||
        url.pathname.startsWith('/public/');
    } catch (_) {
      return false;
    }
  }

  function scrubSecrets(value) {
    return String(value)
      .replace(/([?&](?:sig|token|sesskey)=)[^&]+/gi, '$1[redacted]')
      .replace(/((?:authorization|cookie|csrf|xsrf|token|secret|password|session|sesskey)[\w-]*\s*[:=]\s*)[^&\s,;]+/gi, '$1[redacted]');
  }

  function redactObject(value, depth = 0) {
    if (depth > 8) return '[depth-limit]';
    if (Array.isArray(value)) {
      return value.slice(0, 100).map((item) => redactObject(item, depth + 1));
    }
    if (value && typeof value === 'object') {
      const out = {};
      for (const [key, item] of Object.entries(value)) {
        out[key] = SECRET_KEY.test(key)
          ? '[redacted]'
          : redactObject(item, depth + 1);
      }
      return out;
    }
    if (typeof value === 'string') {
      const scrubbed = scrubSecrets(value);
      return scrubbed.length > MAX_PREVIEW
        ? scrubbed.slice(0, MAX_PREVIEW) + '…'
        : scrubbed;
    }
    return value;
  }

  function sanitizeText(text, contentType = '') {
    if (!text) return '';
    const trimmed = String(text).slice(0, MAX_PREVIEW);
    if (/json/i.test(contentType) || /^[\[{]/.test(trimmed.trim())) {
      try {
        return JSON.stringify(redactObject(JSON.parse(trimmed)));
      } catch (_) {}
    }
    return scrubSecrets(trimmed).slice(0, MAX_PREVIEW);
  }

  function bodyPreview(body) {
    if (body == null) return '';
    if (typeof body === 'string') return sanitizeText(body);
    if (body instanceof URLSearchParams) {
      const out = {};
      for (const [key, value] of body.entries()) {
        out[key] = SECRET_KEY.test(key) ? '[redacted]' : value;
      }
      return JSON.stringify(out).slice(0, MAX_PREVIEW);
    }
    if (body instanceof FormData) {
      const out = {};
      for (const [key, value] of body.entries()) {
        out[key] = SECRET_KEY.test(key)
          ? '[redacted]'
          : value instanceof File
            ? `[file:${value.name}]`
            : String(value);
      }
      return JSON.stringify(out).slice(0, MAX_PREVIEW);
    }
    if (body instanceof Blob) return `[blob ${body.type || 'unknown'} ${body.size} bytes]`;
    if (body instanceof ArrayBuffer) return `[arraybuffer ${body.byteLength} bytes]`;
    try {
      return sanitizeText(JSON.stringify(redactObject(body)), 'application/json');
    } catch (_) {
      return String(body).slice(0, MAX_PREVIEW);
    }
  }

  function emit(event) {
    if (!isRelevantUrl(event.url || '')) return;

    const normalized = {
      timestamp: now(),
      kind: event.kind || 'resource',
      method: (event.method || 'GET').toUpperCase(),
      url: event.url || '',
      status: event.status ?? null,
      contentType: event.contentType || '',
      requestBody: event.requestBody || '',
      responsePreview: event.responsePreview || '',
      durationMs: typeof event.durationMs === 'number'
        ? Math.round(event.durationMs * 10) / 10
        : null,
    };

    buffer.push(normalized);
    if (buffer.length > MAX_EVENTS) {
      buffer.splice(0, buffer.length - MAX_EVENTS);
    }

    flushOne(normalized);
  }

  function flushOne(event) {
    try {
      if (window.flutter_inappwebview?.callHandler) {
        window.flutter_inappwebview.callHandler(
          'betterOqbNetworkEvent',
          JSON.stringify(event)
        );
      } else if (window.BetterOqbNetwork?.postMessage) {
        window.BetterOqbNetwork.postMessage(JSON.stringify(event));
      }
    } catch (_) {}
  }

  function flushAll() {
    for (const event of buffer.slice(-MAX_EVENTS)) {
      flushOne(event);
    }
  }

  const originalFetch = window.fetch?.bind(window);
  if (originalFetch) {
    window.fetch = async function(input, init = {}) {
      const request = input instanceof Request ? input : null;
      const url = request?.url || String(input);
      const method = init.method || request?.method || 'GET';
      const requestBody = bodyPreview(init.body);
      const started = performance.now();

      try {
        const response = await originalFetch(input, init);
        const contentType = response.headers.get('content-type') || '';
        let responsePreview = '';
        try {
          responsePreview = sanitizeText(
            await response.clone().text(),
            contentType
          );
        } catch (_) {}

        emit({
          kind: 'fetch',
          method,
          url,
          status: response.status,
          contentType,
          requestBody,
          responsePreview,
          durationMs: performance.now() - started,
        });
        return response;
      } catch (error) {
        emit({
          kind: 'fetch',
          method,
          url,
          status: 0,
          requestBody,
          responsePreview: String(error),
          durationMs: performance.now() - started,
        });
        throw error;
      }
    };
  }

  const XHR = window.XMLHttpRequest;
  if (XHR?.prototype) {
    const originalOpen = XHR.prototype.open;
    const originalSend = XHR.prototype.send;

    XHR.prototype.open = function(method, url, ...rest) {
      this.__betterOqbMethod = method || 'GET';
      this.__betterOqbUrl = String(url);
      return originalOpen.call(this, method, url, ...rest);
    };

    XHR.prototype.send = function(body) {
      const started = performance.now();
      const requestBody = bodyPreview(body);

      this.addEventListener('loadend', () => {
        let contentType = '';
        let responsePreview = '';
        try {
          contentType = this.getResponseHeader('content-type') || '';
        } catch (_) {}
        try {
          if (this.responseType === '' || this.responseType === 'text') {
            responsePreview = sanitizeText(this.responseText, contentType);
          } else if (this.responseType === 'json') {
            responsePreview = sanitizeText(
              JSON.stringify(redactObject(this.response)),
              'application/json'
            );
          } else {
            responsePreview = `[responseType:${this.responseType || 'unknown'}]`;
          }
        } catch (_) {}

        emit({
          kind: 'xhr',
          method: this.__betterOqbMethod || 'GET',
          url: this.__betterOqbUrl || '',
          status: this.status || 0,
          contentType,
          requestBody,
          responsePreview,
          durationMs: performance.now() - started,
        });
      }, { once: true });

      return originalSend.call(this, body);
    };
  }

  if (navigator.sendBeacon) {
    const originalBeacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      emit({
        kind: 'beacon',
        method: 'POST',
        url: String(url),
        requestBody: bodyPreview(data),
      });
      return originalBeacon(url, data);
    };
  }

  try {
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!(entry instanceof PerformanceResourceTiming)) continue;
        if (!['fetch', 'xmlhttprequest', 'beacon'].includes(entry.initiatorType)) continue;
        emit({
          kind: `resource:${entry.initiatorType}`,
          method: 'GET',
          url: entry.name,
          durationMs: entry.duration,
        });
      }
    });
    observer.observe({ type: 'resource', buffered: true });
  } catch (_) {}

  window.addEventListener('flutterInAppWebViewPlatformReady', flushAll);
  window.addEventListener('load', () => setTimeout(flushAll, 300));

  window.betterOqbNetwork = {
    getEvents() {
      return buffer.slice();
    },
    clear() {
      buffer.splice(0, buffer.length);
      return true;
    },
    flush: flushAll,
  };
})();
