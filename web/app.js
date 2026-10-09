async function api(path, method, body) {
  const opts = { method: method || 'GET', credentials: 'same-origin', headers: {} };
  if (opts.method !== 'GET') {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body || {});
  }
  const r = await fetch('/api' + path, opts);
  let data = null;
  try { data = await r.json(); } catch (e) {}
  if (!r.ok) {
    const err = new Error((data && data.error) || 'Request failed');
    err.status = r.status;
    throw err;
  }
  return data;
}

// Builds DOM nodes with textContent only, so user-supplied text is never parsed as HTML
function el(tag, props, ...kids) {
  const e = document.createElement(tag);
  Object.assign(e, props || {});
  kids.forEach((k) => e.append(k));
  return e;
}

async function renderNav() {
  const nav = document.getElementById('nav');
  nav.replaceChildren(
    el('a', { href: '/', textContent: 'Shop' }),
    el('a', { href: '/cart', textContent: 'Cart' })
  );
  try {
    const me = await api('/auth/me');
    nav.append(
      el('span', { textContent: 'Hi, ' + me.name }),
      el('a', {
        href: '#', textContent: 'Logout',
        onclick: async (ev) => {
          ev.preventDefault();
          await api('/auth/logout', 'POST');
          location.href = '/';
        },
      })
    );
    return me;
  } catch (e) {
    nav.append(el('a', { href: '/login', textContent: 'Login' }));
    return null;
  }
}
