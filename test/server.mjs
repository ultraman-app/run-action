// The self-test's API: GET /hello answers 200 only with the expected bearer token and user, 401 otherwise.
import { createServer } from 'node:http';

const port = Number(process.argv[2] ?? 4387);
createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://x');
  const ok = url.pathname === '/hello' && req.headers.authorization === `Bearer ${process.env.EXPECTED_TOKEN}` && url.searchParams.get('user') === 'ana';
  res.writeHead(ok ? 200 : 401, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ ok }));
}).listen(port, '127.0.0.1', () => console.log(`listening on ${port}`));
