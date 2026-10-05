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

    node = input.parentElement;
    for (let depth = 0; node && depth < 6; depth++, node = node.parentElement) {
      const radios = node.querySelectorAll('input[type="radio"]').length;
      const text = clean(node.innerText);
      if (radios === 1 && text.length > 0 && text.length < 2500) return node;
    }
    return input.parentElement || input;
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
    const radios = [...document.querySelectorAll('input[type="radio"]')].filter(visible);
    if (radios.length < 2 || radios.length > 12) return null;

    const optionNodes = radios.map(optionContainer);
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

    const rootClone = root.cloneNode(true);
    rootClone.querySelectorAll('script,style,noscript,button,input,select,textarea').forEach((e) => e.remove());

    optionNodes.forEach((original) => {
      const marker = original.getAttribute('data-better-oqb-option-marker') ||
        `boqb-${Math.random().toString(36).slice(2)}`;
      original.setAttribute('data-better-oqb-option-marker', marker);
      const found = rootClone.querySelector(`[data-better-oqb-option-marker="${marker}"]`);
      found?.remove();
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

    const state = {
      url: location.href,
      title: document.title,
      headings,
      actions,
      isLoggedIn: !/login|sign in|登入/i.test(document.body?.innerText || ''),
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

  addEventListener('popstate', schedule);
  addEventListener('hashchange', schedule);
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
