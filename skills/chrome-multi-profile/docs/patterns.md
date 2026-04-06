# JavaScript Injection Patterns

Recipes for common tasks when running JavaScript in a Chrome tab via the `chrome_js` helper. All examples assume you have already resolved `WIN` and `TAB` via `chrome_window_for` and `chrome_tab_for_url`.

## Basic value return

`osascript`-executed JS returns its result as a string. Wrap in an IIFE for clarity:

```bash
chrome_js "$WIN" "$TAB" "(function(){ return document.title; })()"
```

For anything more complex than a single expression, build a multi-line string via Python so you don't have to escape bash + AppleScript quoting twice.

## Multi-line JS via Python

```python
import subprocess

def chrome_js(win_id, tab_id, js):
    escaped = js.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))
    cmd = f'tell application "Google Chrome" to execute (tab id "{tab_id}" of window id "{win_id}") javascript "{escaped}"'
    result = subprocess.run(['osascript', '-e', cmd], capture_output=True, text=True)
    return result.stdout.strip()
```

Use it with any JS:

```python
out = chrome_js(WIN, TAB, '''(function(){
  const rows = document.querySelectorAll('tr.zA');
  return JSON.stringify(Array.from(rows).slice(0, 10).map(r => ({
    sender: (r.querySelector('.yW span') || {}).textContent || '',
    subject: (r.querySelector('.bog') || {}).textContent || '',
    snippet: (r.querySelector('.y2') || {}).textContent || '',
  })));
})()''')
```

## Returning structured data

`osascript` returns plain strings. To get structured data, return JSON from the JS and parse it on the host side:

```python
import json

raw = chrome_js(WIN, TAB, '''(function(){
  return JSON.stringify({
    url: location.href,
    title: document.title,
    cookies_len: document.cookie.length,
  });
})()''')
data = json.loads(raw)
print(data['url'], data['title'])
```

## Filling form inputs (React-safe)

React and Vue intercept native property setters. Using `input.value = 'x'` directly doesn't trigger the framework's internal state update, and the input reverts on the next render. Use the native prototype setter:

```javascript
(function(){
  const input = document.querySelector('input[name="email"]');
  if (!input) return 'no input';
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  setter.call(input, 'user@example.com');
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
  return 'filled: ' + input.value;
})()
```

For `<textarea>`, use `HTMLTextAreaElement.prototype`.

For contenteditable (LinkedIn, Slack, Discord), framework intercepts are harder. Focus the element and use `document.execCommand('insertText', false, 'text')` — falls back to paste-equivalent behavior that most rich text editors honor.

## Clicking buttons by visible text

```javascript
(function(){
  const btns = document.querySelectorAll('button, a, [role="button"]');
  for (let i = 0; i < btns.length; i++) {
    if ((btns[i].textContent || '').trim() === 'Submit') {
      btns[i].click();
      return 'clicked';
    }
  }
  return 'not found';
})()
```

## Authenticated-element check

Before running automation on a session-gated page, verify you're logged in:

```javascript
// Gmail
(!!document.querySelector('a[aria-label*="Google Account"]')) + ''

// ProtonMail
(!!document.querySelector('[data-testid="heading:userdropdown"]')) + ''

// GitHub
(!!document.querySelector('meta[name="user-login"]')) + ''

// LinkedIn (on /messaging/)
(!!document.querySelector('.msg-conversation-listitem')) + ''

// Twitter/X
(!!document.querySelector('a[href="/compose/post"]')) + ''
```

A `"true"` return means logged in; `"false"` means a redirect or logout happened silently.

## Scrolling

```javascript
// Scroll to bottom
window.scrollTo(0, document.body.scrollHeight);

// Scroll a specific element into view
(function(){
  const el = document.querySelector('#target');
  if (el) el.scrollIntoView({ behavior: 'instant', block: 'center' });
})()
```

## Waiting for dynamic content

AppleScript-executed JS is synchronous — it does not `await`. Two patterns for waiting:

### Pattern 1: Poll with sleep between calls

```bash
for i in 1 2 3 4 5; do
  RESULT=$(chrome_js "$WIN" "$TAB" "(!!document.querySelector('.loaded-marker')) + ''")
  [ "$RESULT" = "true" ] && break
  sleep 1
done
```

### Pattern 2: setTimeout + document.title sentinel

When you need to trigger an async operation and wait for its completion from the host side:

```javascript
// In the first JS call: start the async work and set the title as a flag
(function(){
  document.title = '__WAITING__';
  fetch('/api/data').then(r => r.json()).then(data => {
    window.__result = data;
    document.title = '__DONE__';
  }).catch(e => {
    document.title = '__ERROR__';
  });
  return 'started';
})()
```

Then from the host side, poll `document.title` until it changes, and finally read `window.__result`.

## Tunneling large data via localStorage

`osascript` return values are truncated at around 256 KB. For larger payloads, write to `localStorage` in one call and read it in a separate call, chunking if necessary:

```javascript
// Write
(function(){
  const bigData = JSON.stringify({...});
  localStorage.setItem('__claude_tunnel', bigData);
  return 'wrote ' + bigData.length + ' bytes';
})()

// Read (possibly chunked)
(function(){
  return localStorage.getItem('__claude_tunnel') || '';
})()

// Clean up
(function(){
  localStorage.removeItem('__claude_tunnel');
  return 'cleaned';
})()
```

## Dispatching real mouse events (for React-intercepted elements)

If a framework intercepts `click()` via its synthetic event system (common in LinkedIn, Discord), native `.click()` may not propagate. Dispatch a real mouse event sequence instead:

```javascript
(function(){
  const el = document.querySelector('.target');
  if (!el) return 'not found';
  const rect = el.getBoundingClientRect();
  const opts = {
    bubbles: true,
    cancelable: true,
    view: window,
    clientX: rect.left + rect.width / 2,
    clientY: rect.top + rect.height / 2,
    button: 0,
  };
  el.dispatchEvent(new MouseEvent('mousedown', opts));
  el.dispatchEvent(new MouseEvent('mouseup', opts));
  el.dispatchEvent(new MouseEvent('click', opts));
  return 'clicked';
})()
```

If that still doesn't work, the framework is using a deeper abstraction — fall back to focusing + keyboard events (Tab to the element, Enter to activate) or use the element's own handler via React Fiber inspection.

## Keyboard shortcuts

```javascript
(function(){
  const el = document.activeElement || document.body;
  el.dispatchEvent(new KeyboardEvent('keydown', {
    key: 'Enter',
    code: 'Enter',
    keyCode: 13,
    which: 13,
    bubbles: true,
    cancelable: true,
  }));
  return 'sent Enter';
})()
```

## Reading iframes (e.g. email bodies, sandboxed content)

ProtonMail, some webmails, and several rich text editors render content in sandboxed iframes. Querying the main `document` misses them:

```javascript
(function(){
  const ifs = document.querySelectorAll('iframe');
  for (let i = 0; i < ifs.length; i++) {
    try {
      const doc = ifs[i].contentDocument;
      if (doc && doc.body) {
        const t = (doc.body.innerText || '').replace(/\s+/g, ' ');
        if (t.length > 50) return t.slice(0, 2000);
      }
    } catch (e) {
      // cross-origin, skip
    }
  }
  return 'no content';
})()
```

Same-origin iframes are readable; cross-origin ones throw a SecurityError and must be skipped.

## Getting paste content via Cmd+V (for stubborn contenteditables)

Some compose boxes reject programmatic `execCommand('insertText')`. Paste works because the clipboard event is honored by nearly all frameworks.

```bash
# Set the clipboard via pbcopy
printf '%s' "Your message here" | pbcopy

# Focus the compose box via JS (or click it)
chrome_js "$WIN" "$TAB" "document.querySelector('.compose-box').focus()"

# Bring Chrome to front and paste via System Events
osascript <<EOF
tell application "Google Chrome" to activate
delay 0.3
tell application "System Events" to keystroke "v" using {command down}
EOF
```

This works for LinkedIn, Slack, Discord, Notion, and most other rich text editors that programmatic JS injection fails against.

## Error handling patterns

Wrap fragile operations in try/catch and return a status string:

```javascript
(function(){
  try {
    const r = doSomethingRisky();
    return JSON.stringify({ ok: true, result: r });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e).slice(0, 200) });
  }
})()
```

Always return a string — `osascript` cannot represent objects directly and will display `missing value` for anything that's not a string, number, boolean, or list.
