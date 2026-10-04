(() => {
  if (window.__betterOqbInstalled) return;
  window.__betterOqbInstalled = true;

  const clean = (value) => (value || '').replace(/\s+/g, ' ').trim();
  const unique = (items) => [...new Set(items.filter(Boolean))].slice(0, 80);

  function snapshot() {
    const headings = unique(
      [...document.querySelectorAll('h1,h2,h3,[role="heading"]')]
        .map((element) => clean(element.innerText))
    );
    const actions = unique(
      [...document.querySelectorAll('button,[role="button"],a')]
        .map((element) => clean(element.innerText || element.getAttribute('aria-label')))
    );

    const state = {
      url: location.href,
      title: document.title,
      headings,
      actions,
      isLoggedIn: !/login|sign in|登入/i.test(document.body?.innerText || ''),
    };

    const encoded = JSON.stringify(state);

    if (window.flutter_inappwebview?.callHandler) {
      window.flutter_inappwebview.callHandler('betterOqbPageState', encoded);
    }
    if (window.BetterOqb?.postMessage) {
      window.BetterOqb.postMessage(encoded);
    }
  }

  let timer;
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(snapshot, 120);
  };

  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true,
    childList: true,
    characterData: true,
  });

  addEventListener('popstate', schedule);
  addEventListener('hashchange', schedule);
  addEventListener('load', schedule);
  snapshot();

  window.betterOqb = {
    snapshot,
    clickByText(text) {
      const wanted = clean(text).toLowerCase();
      const candidates = [...document.querySelectorAll('button,[role="button"],a,label')];
      const target = candidates.find(
        (element) => clean(element.innerText).toLowerCase() === wanted
      );
      if (!target) return false;
      target.click();
      return true;
    },
  };
})();
