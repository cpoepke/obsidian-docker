#!/usr/bin/env python3
"""Enable Obsidian community plugins via Chrome DevTools Protocol.

Connects to Obsidian's remote debugging port (9222), dismisses any modals,
disables restricted mode, and initializes all community plugins.
"""

import json
import asyncio
import urllib.request
import websockets


CDP_URL = "http://127.0.0.1:9222/json"
MAX_RETRIES = 10
RETRY_DELAY = 2
WS_TIMEOUT = 15

JS_ENABLE_PLUGINS = """
(async () => {
    // Dismiss any open modals (e.g., release notes, update prompts)
    document.querySelectorAll('.modal-close-button').forEach(b => b.click());

    const p = app.plugins;
    // Disable restricted mode
    p.setEnable(true);
    // Load manifests and initialize all enabled plugins
    await p.loadManifests();
    await p.initialize();

    const loaded = Object.keys(p.plugins);
    const results = ['Loaded ' + loaded.length + ' plugins: ' + loaded.join(', ')];

    // Check REST API plugin status
    const rest = p.plugins['obsidian-local-rest-api'];
    if (rest) {
        results.push('REST API plugin settings: ' + JSON.stringify(rest.settings || rest.data || {}));
    }

    return results.join('\\n');
})()
"""


async def cdp_eval(ws, expr, await_promise=True, msg_id=1):
    """Send a CDP Runtime.evaluate and return the result."""
    await ws.send(json.dumps({
        "id": msg_id,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expr,
            "awaitPromise": await_promise,
            "returnByValue": True,
        },
    }))
    # Read responses until we get our result (skip events)
    while True:
        raw = await asyncio.wait_for(ws.recv(), timeout=WS_TIMEOUT)
        result = json.loads(raw)
        if result.get("id") == msg_id:
            return result


async def enable_plugins():
    # Wait for CDP endpoint to be available
    ws_url = None
    for attempt in range(MAX_RETRIES):
        try:
            data = json.loads(urllib.request.urlopen(CDP_URL, timeout=3).read())
            ws_url = data[0]["webSocketDebuggerUrl"]
            break
        except Exception:
            if attempt < MAX_RETRIES - 1:
                await asyncio.sleep(RETRY_DELAY)

    if not ws_url:
        print("ERROR: Could not connect to CDP endpoint")
        return False

    try:
        async with websockets.connect(ws_url, close_timeout=3) as ws:
            result = await cdp_eval(ws, JS_ENABLE_PLUGINS)
            exception = result.get("result", {}).get("exceptionDetails")
            if exception:
                desc = exception.get("exception", {}).get("description", "unknown")
                print(f"ERROR: {desc}")
                return False

            value = result.get("result", {}).get("result", {}).get("value", "")
            print(f"CDP: {value}")
            return True
    except asyncio.TimeoutError:
        print("ERROR: CDP response timed out")
        return False
    except Exception as e:
        print(f"ERROR: {e}")
        return False


if __name__ == "__main__":
    success = asyncio.run(enable_plugins())
    raise SystemExit(0 if success else 1)
