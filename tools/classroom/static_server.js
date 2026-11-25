#!/usr/bin/env node
// Minimal static file server for the classroom download page (no dependencies).
// Serves ONLY the files that sit directly or below --root; GET/HEAD only; no directory listing;
// rejects any path that resolves outside the root (".." , encoded "..", absolute paths, NUL, etc.).
//
//   node tools/classroom/static_server.js --root <dir> [--port 8088] [--host 0.0.0.0]
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const rootArg = arg('root');
if (!rootArg) {
  console.error('usage: static_server.js --root <dir> [--port 8088] [--host 0.0.0.0]');
  process.exit(2);
}
const ROOT = fs.realpathSync(path.resolve(rootArg));
const PORT = Number(arg('port', '8088'));
const HOST = arg('host', '0.0.0.0');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.sha256': 'text/plain; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.apk': 'application/vnd.android.package-archive',
  '.ps1': 'text/plain; charset=utf-8',
  '.cmd': 'application/octet-stream',
};

function send(res, status, text) {
  res.writeHead(status, {
    'Content-Type': 'text/plain; charset=utf-8',
    'X-Content-Type-Options': 'nosniff',
    'Cache-Control': 'no-store',
  });
  res.end(text);
}

// Returns the absolute file path inside ROOT, or null when the request must be refused.
function resolveInsideRoot(rawUrl) {
  let pathname;
  try {
    pathname = new URL(rawUrl, 'http://localhost').pathname;
    pathname = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (pathname.includes('\0') || pathname.includes('\\') || pathname.includes(':')) return null;
  const segments = pathname.split('/').filter((s) => s.length > 0);
  if (segments.some((s) => s === '..' || s === '.' || s.startsWith('.'))) return null; // also hides dotfiles
  if (segments.length === 0) segments.push('index.html');
  const candidate = path.resolve(ROOT, ...segments);
  const rel = path.relative(ROOT, candidate);
  if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) return null;
  let real;
  try {
    real = fs.realpathSync(candidate); // defeats symlinks / junctions pointing outside
  } catch {
    return undefined; // not found
  }
  const relReal = path.relative(ROOT, real);
  if (relReal === '' || relReal.startsWith('..') || path.isAbsolute(relReal)) return null;
  return real;
}

const server = http.createServer((req, res) => {
  const stamp = new Date().toISOString();
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD');
    send(res, 405, 'Method not allowed\n');
    console.log(`${stamp} ${req.socket.remoteAddress} ${req.method} ${req.url} 405`);
    return;
  }
  const file = resolveInsideRoot(req.url || '/');
  if (file === null) {
    send(res, 403, 'Forbidden\n');
    console.log(`${stamp} ${req.socket.remoteAddress} ${req.method} ${req.url} 403`);
    return;
  }
  let st;
  try {
    st = file ? fs.statSync(file) : null;
  } catch {
    st = null;
  }
  if (!st || !st.isFile()) {
    send(res, 404, 'Not found\n');
    console.log(`${stamp} ${req.socket.remoteAddress} ${req.method} ${req.url} 404`);
    return;
  }
  const ext = path.extname(file).toLowerCase();
  const headers = {
    'Content-Type': TYPES[ext] || 'application/octet-stream',
    'Content-Length': st.size,
    'X-Content-Type-Options': 'nosniff',
    'Cache-Control': 'no-store',
  };
  if (ext === '.apk' || ext === '.cmd') headers['Content-Disposition'] = `attachment; filename="${path.basename(file)}"`;
  res.writeHead(200, headers);
  console.log(`${stamp} ${req.socket.remoteAddress} ${req.method} ${req.url} 200`);
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  const stream = fs.createReadStream(file);
  stream.on('error', () => res.destroy());
  stream.pipe(res);
});

server.on('error', (err) => {
  console.error(`static_server: ${err.message}`);
  process.exit(1);
});
server.listen(PORT, HOST, () => {
  console.log(`static_server: serving ${ROOT} on http://${HOST}:${PORT}/`);
});

function stop() {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1000).unref();
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
process.on('SIGBREAK', stop);
