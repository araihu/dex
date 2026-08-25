import { createServer } from 'node:http';

const upstream = new URL(process.env.DEX_TEST_UPSTREAM ?? '');
const port = Number.parseInt(process.env.DEX_TEST_PROXY_PORT ?? '', 10);

if (upstream.protocol !== 'http:' || upstream.pathname !== '/' || !Number.isInteger(port) || port < 1) {
  throw new Error('DEX_TEST_UPSTREAM and DEX_TEST_PROXY_PORT are required');
}

export const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'none'",
  "connect-src 'self'",
  "font-src 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "img-src 'self' data:",
  "object-src 'none'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
].join('; ');

const server = createServer((request, response) => {
  const target = new URL(request.url ?? '/', upstream);
  const proxyRequest = fetch(target, {
    method: request.method,
    headers: request.headers,
    body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request,
    redirect: 'manual',
    duplex: 'half',
  });

  proxyRequest.then(async (upstreamResponse) => {
    const headers = Object.fromEntries(upstreamResponse.headers);
    headers['content-security-policy'] = contentSecurityPolicy;
    delete headers['content-length'];
    response.writeHead(upstreamResponse.status, headers);
    if (upstreamResponse.body) {
      for await (const chunk of upstreamResponse.body) response.write(chunk);
    }
    response.end();
  }).catch((error) => {
    response.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(`proxy error: ${error.message}\n`);
  });
});

server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`csp-proxy: http://127.0.0.1:${port}\n`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
