const http = require('node:http');

function getServiceInfo() {
  return {
    status: 'ok',
    service: process.env.K_SERVICE || 'starter-service',
    revision: process.env.K_REVISION || 'local-dev',
    configuration: process.env.K_CONFIGURATION || 'local',
    commitSha: process.env.COMMIT_SHA || 'local',
    deployTag: process.env.DEPLOY_TAG || 'default',
    nodeVersion: process.version,
    timestamp: new Date().toISOString(),
  };
}

function renderHtml(info) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${info.service} — Cloud Run Starter</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, -apple-system, sans-serif; }
    body { margin: 0; padding: 2rem; display: grid; place-items: center; min-height: 100vh; box-sizing: border-box; background: #0f172a; color: #e2e8f0; }
    .card { width: 100%; max-width: 640px; background: #1e293b; border: 1px solid #334155; border-radius: 14px; padding: 2rem; box-shadow: 0 20px 45px rgba(0,0,0,0.35); }
    h1 { margin-top: 0; font-size: 1.75rem; display: flex; align-items: center; gap: 0.6rem; }
    .badge { display: inline-block; padding: 0.2rem 0.65rem; border-radius: 999px; font-size: 0.8rem; font-weight: 600; background: #065f46; color: #6ee7b7; }
    dl { display: grid; grid-template-columns: 150px 1fr; gap: 0.65rem 1rem; margin: 1.5rem 0; }
    dt { color: #94a3b8; font-weight: 600; }
    dd { margin: 0; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; word-break: break-all; }
    pre { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 1rem; overflow-x: auto; font-size: 0.85rem; }
  </style>
</head>
<body>
  <main class="card">
    <h1>${info.service} <span class="badge" id="health-badge">checking...</span></h1>
    <p>End-to-end GitHub &rarr; Cloud Build &rarr; Cloud Run verification dashboard.</p>
    <dl>
      <dt>Revision</dt><dd>${info.revision}</dd>
      <dt>Commit SHA</dt><dd>${info.commitSha}</dd>
      <dt>Deploy Tag</dt><dd>${info.deployTag}</dd>
      <dt>Node.js</dt><dd>${info.nodeVersion}</dd>
    </dl>
    <h3>Live <code>/health</code> Response</h3>
    <pre id="health-json">Loading...</pre>
  </main>
  <script>
    fetch('/health')
      .then((res) => res.json())
      .then((data) => {
        document.getElementById('health-badge').textContent = data.status === 'ok' ? 'healthy' : 'degraded';
        document.getElementById('health-json').textContent = JSON.stringify(data, null, 2);
      })
      .catch((err) => {
        document.getElementById('health-badge').textContent = 'error';
        document.getElementById('health-json').textContent = String(err);
      });
  </script>
</body>
</html>`;
}

function createServer() {
  return http.createServer((req, res) => {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

    if (url.pathname === '/health') {
      const payload = JSON.stringify(getServiceInfo(), null, 2);
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(payload);
      return;
    }

    if (url.pathname === '/') {
      const html = renderHtml(getServiceInfo());
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Not Found', path: url.pathname }));
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8080);
  const server = createServer();
  server.listen(port, '0.0.0.0', () => {
    console.log(`starter-service listening on http://localhost:${port}`);
  });
}

module.exports = { createServer, getServiceInfo };
