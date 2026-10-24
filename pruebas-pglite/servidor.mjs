// Servidor local de prueba: imita el endpoint RPC de Supabase (PostgREST) sobre PGlite, en memoria.
// Solo para recorrer la aplicación en el navegador sin tocar la base publicada. Datos ficticios de las migraciones.
// Uso: node servidor.mjs [puerto]   (por defecto 54321)
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const repo = 'C:/Users/mateo/code/motores-pesadosv1/server';
const puerto = Number(process.argv[2] || 54321);
const db = await PGlite.create({ extensions: { pgcrypto } });
await db.exec(readFileSync(join(repo, 'tests/stub_supabase.sql'), 'utf8'));
const dir = join(repo, 'supabase/migrations');
for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) await db.exec(readFileSync(join(dir, f), 'utf8'));
console.log('Migraciones aplicadas en PGlite.');

const cabeceras = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' };

createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, cabeceras); res.end(); return; }
  const m = /^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(req.url.split('?')[0]);
  if (!m || req.method !== 'POST') { res.writeHead(404, cabeceras); res.end('{}'); return; }
  let cuerpo = '';
  req.on('data', (c) => { cuerpo += c; });
  req.on('end', async () => {
    try {
      const args = cuerpo ? JSON.parse(cuerpo) : {};
      const claves = Object.keys(args);
      const valores = claves.map((k) => (args[k] === null ? null : typeof args[k] === 'object' ? JSON.stringify(args[k]) : String(args[k])));
      const sql = `select public.${m[1]}(${claves.map((k, i) => `${k} => $${i + 1}`).join(', ')}) as r`;
      const { rows } = await db.query(sql, valores);
      res.writeHead(200, { ...cabeceras, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(rows[0]?.r ?? null));
    } catch (e) {
      res.writeHead(400, { ...cabeceras, 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ code: e.code ?? 'P0001', message: e.message, details: e.detail ?? null, hint: e.hint ?? null }));
    }
  });
}).listen(puerto, () => console.log(`API de prueba en http://localhost:${puerto}`));
