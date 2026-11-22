const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../src/server');

async function withServer(fn) {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;
  try {
    await fn(baseUrl);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('GET /health returns 200 OK with service metadata', async () => {
  await withServer(async (baseUrl) => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, 'ok');
    assert.ok(body.service);
    assert.ok(body.revision);
    assert.ok(body.timestamp);
  });
});

test('GET / returns 200 HTML dashboard', async () => {
  await withServer(async (baseUrl) => {
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 200);
    const contentType = res.headers.get('content-type') || '';
    assert.match(contentType, /text\/html/);
    const html = await res.text();
    assert.match(html, /Cloud Run Starter/);
    assert.match(html, /\/health/);
  });
});

test('GET /unknown returns 404 JSON', async () => {
  await withServer(async (baseUrl) => {
    const res = await fetch(`${baseUrl}/unknown`);
    assert.equal(res.status, 404);
    const body = await res.json();
    assert.equal(body.error, 'Not Found');
  });
});
