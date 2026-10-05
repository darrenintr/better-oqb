(() => {
  if (window.__betterOqbInstalled) return;
  window.__betterOqbInstalled = true;

  const clean = (value) => (value || '').replace(/\s+/g, ' ').trim();
  const unique = (items) => [...new Set(items.filter(Boolean))].slice(0, 80);
  const visible = (element) => {
    if (!(element instanceof Element)) return false;
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      rect.width > 0 &&
      rect.height > 0;
  };

  function absolutize(root) {
    root.querySelectorAll('[src]').forEach((element) => {
      const value = element.getAttribute('src');
      if (!value) return;
      try {
        element.setAttribute('src', new URL(value, location.href).href);
      } catch (_) {}
    });
    root.querySelectorAll('[href]').forEach((element) => {
      const value = element.getAttribute('href');
      if (!value) return;
      try {
        element.setAttribute('href', new URL(value, location.href).href);
      } catch (_) {}
    });
  }

  function optionContainer(input) {
    let node = input.closest('label');
    if (node && visible(node)) return node;

    const associatedLabel = [...(input.labels || [])].find(visible);
    if (associatedLabel) return associatedLabel;

    node = input.parentElement;
    let fallback = null;
    for (let depth = 0; node && depth < 6; depth++, node = node.parentElement) {
      if (visible(node) && fallback == null) fallback = node;
      const radios = node.querySelectorAll('input[type="radio"]').length;
      const text = clean(node.innerText);
      if (
        visible(node) &&
        radios === 1 &&
        text.length > 0 &&
        text.length < 2500
      ) {
        return node;
      }
    }
    return fallback || input.parentElement || input;
  }

  function commonAncestor(nodes) {
    if (!nodes.length) return null;
    let candidate = nodes[0];
    while (candidate && candidate !== document.body) {
      if (nodes.every((node) => candidate.contains(node))) return candidate;
      candidate = candidate.parentElement;
    }
    return document.body;
  }

  function questionRoot(optionNodes) {
    let root = commonAncestor(optionNodes);
    if (!root) return null;

    for (let depth = 0; root.parentElement && depth < 5; depth++) {
      const parent = root.parentElement;
      const radioCount = parent.querySelectorAll('input[type="radio"]').length;
      const textLength = clean(parent.innerText).length;
      if (radioCount >= optionNodes.length && radioCount <= 12 && textLength < 12000) {
        root = parent;
      } else {
        break;
      }
    }
    return root;
  }

  function cloneHtml(node, removeNodes = []) {
    if (!node) return '';
    const clone = node.cloneNode(true);
    clone.querySelectorAll('script,style,noscript,input,button,select,textarea').forEach((e) => e.remove());
    clone.querySelectorAll('[onclick],[onchange],[onmousedown],[onmouseup]').forEach((e) => {
      e.removeAttribute('onclick');
      e.removeAttribute('onchange');
      e.removeAttribute('onmousedown');
      e.removeAttribute('onmouseup');
    });
    removeNodes.forEach((original) => {
      if (!original || !original.parentElement) return;
      const path = [];
      let cursor = original;
      while (cursor && cursor !== node) {
        const parent = cursor.parentElement;
        if (!parent) break;
        path.unshift([...parent.children].indexOf(cursor));
        cursor = parent;
      }
      let target = clone;
      for (const index of path) {
        target = target?.children?.[index];
        if (!target) break;
      }
      target?.remove();
    });
    absolutize(clone);
    return clone.innerHTML;
  }

  function extractQuestion() {
    const candidates = [...document.querySelectorAll('input[type="radio"]')]
      .map((input) => ({ input, container: optionContainer(input) }))
      .filter(({ container }) => visible(container));

    if (candidates.length < 2) return null;

    let selected = candidates;
    if (selected.length > 12) {
      const groups = new Map();
      for (const candidate of selected) {
        const name = candidate.input.getAttribute('name') || '__anonymous__';
        if (!groups.has(name)) groups.set(name, []);
        groups.get(name).push(candidate);
      }

      const plausible = [...groups.values()]
        .filter((group) => group.length >= 2 && group.length <= 12)
        .sort((a, b) => b.length - a.length);

      if (plausible.length === 0) return null;
      selected = plausible[0];
    }

    const radios = selected.map(({ input }) => input);
    const optionNodes = selected.map(({ container }) => container);
    const root = questionRoot(optionNodes);
    if (!root) return null;

    const options = radios.map((input, index) => {
      const container = optionNodes[index];
      const key = input.id || input.value || `option-${index}`;
      input.dataset.betterOqbKey = key;

      const text = clean(container.innerText);
      const explicit = text.match(/^([A-H])(?:[.\s、:：]|$)/i);
      const label = explicit ? explicit[1].toUpperCase() : String.fromCharCode(65 + index);

      const clone = container.cloneNode(true);
      clone.querySelectorAll('input,button').forEach((e) => e.remove());
      absolutize(clone);

      return {
        key,
        label,
        html: clone.innerHTML,
        selected: input.checked === true,
      };
    });

    const markers = optionNodes.map((original, index) => {
      const marker = `boqb-option-${index}`;
      original.setAttribute('data-better-oqb-option-marker', marker);
      return marker;
    });

    const rootClone = root.cloneNode(true);
    rootClone.querySelectorAll('script,style,noscript,button,input,select,textarea').forEach((e) => e.remove());

    markers.forEach((marker) => {
      rootClone
        .querySelector(`[data-better-oqb-option-marker="${marker}"]`)
        ?.remove();
    });
    optionNodes.forEach((original) => {
      original.removeAttribute('data-better-oqb-option-marker');
    });

    rootClone.querySelectorAll('a').forEach((a) => {
      const text = clean(a.innerText);
      if (/^(返回|上一頁|下一頁|Previous|Next)$/i.test(text)) a.remove();
    });
    absolutize(rootClone);

    const bodyText = clean(document.body?.innerText || '');
    let current = 0;
    let total = 0;

    const progressMatch = bodyText.match(/試題\s*(\d+)\s*\/\s*(\d+)/);
    if (progressMatch) {
      current = Number(progressMatch[1]);
      total = Number(progressMatch[2]);
    }

    if (!current) {
      const routeMatch = location.pathname.match(/\/do\/(\d+)/);
      if (routeMatch) current = Number(routeMatch[1]);
    }

    return {
      current,
      total,
      html: rootClone.innerHTML,
      options,
    };
  }

  function questionRouteState() {
    const match = location.pathname.match(
      /^\/paper\/(\d+)\/do(?:\/(\d+))?\/?$/
    );
    return {
      isQuestionRoute: Boolean(match),
      paperId: match ? Number(match[1]) : 0,
      questionNumber: match?.[2] ? Number(match[2]) : 0,
    };
  }

  function snapshot() {
    const headings = unique(
      [...document.querySelectorAll('h1,h2,h3,[role="heading"]')]
        .filter(visible)
        .map((element) => clean(element.innerText))
    );
    const actions = unique(
      [...document.querySelectorAll('button,[role="button"],a')]
        .filter(visible)
        .map((element) => clean(element.innerText || element.getAttribute('aria-label')))
    );

    const route = questionRouteState();
    const state = {
      url: location.href,
      title: document.title,
      headings,
      actions,
      isLoggedIn: !/login|sign in|登入/i.test(document.body?.innerText || ''),
      isQuestionRoute: route.isQuestionRoute,
      routeQuestionNumber: route.questionNumber,
      question: extractQuestion(),
    };

    const encoded = JSON.stringify(state);

    if (window.flutter_inappwebview?.callHandler) {
      window.flutter_inappwebview.callHandler('betterOqbPageState', encoded);
    }
    if (window.BetterOqb?.postMessage) {
      window.BetterOqb.postMessage(encoded);
    }
  }

  function clickMatching(texts) {
    const wanted = texts.map((text) => clean(text).toLowerCase());
    const candidates = [...document.querySelectorAll('button,[role="button"],a,label')]
      .filter(visible);
    const target = candidates.find((element) =>
      wanted.includes(clean(element.innerText || element.getAttribute('aria-label')).toLowerCase())
    );
    if (!target) return false;
    target.click();
    return true;
  }

  let timer;
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(snapshot, 140);
  };

  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ['checked', 'class', 'aria-checked', 'aria-selected'],
  });

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    if (typeof original !== 'function') continue;
    history[method] = function(...args) {
      const result = original.apply(this, args);
      schedule();
      return result;
    };
  }

  addEventListener('popstate', schedule);
  addEventListener('hashchange', schedule);
  addEventListener('pageshow', schedule);
  addEventListener('load', schedule);

  window.betterOqb = {
    snapshot,
    answer(key) {
      const escaped = window.CSS?.escape ? CSS.escape(key) : key.replace(/"/g, '\\"');
      const input = document.querySelector(
        `input[type="radio"][data-better-oqb-key="${escaped}"]`
      );
      if (!input) return false;
      input.click();
      input.dispatchEvent(new Event('change', { bubbles: true }));
      schedule();
      return true;
    },
    previous() {
      return clickMatching(['上一頁', 'Previous', 'Prev']);
    },
    next() {
      return clickMatching(['下一頁', 'Next']);
    },
    submit() {
      return clickMatching(['提交', 'Submit']);
    },
    back() {
      return clickMatching(['返回', 'Back']);
    },
  };

  snapshot();
})();
