// Corre las pruebas de SQL del repositorio con PGlite (sin Postgres instalado).
// Uso: node correr.mjs [ruta del repositorio]
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const repo = process.argv[2] || 'C:/Users/mateo/code/motores-pesadosv1';
const server = join(repo, 'server');
const db = await PGlite.create({ extensions: { pgcrypto } });

// Saca los comandos de psql (líneas que empiezan con barra invertida)
const sinPsql = (t) => t.split(/\r?\n/).filter((l) => !l.startsWith('\\')).join('\n');

async function aplicar(nombre, sql) {
  try { await db.exec(sql); }
  catch (e) { console.error(`FALLA al aplicar ${nombre}: ${e.message}`); process.exit(1); }
}

await aplicar('stub_supabase.sql', readFileSync(join(server, 'tests/stub_supabase.sql'), 'utf8'));
const dir = join(server, 'supabase/migrations');
for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
  await aplicar(f, readFileSync(join(dir, f), 'utf8'));
}
console.log('Migraciones aplicadas.');

// Las pruebas: se corta el final (la excepción y el rollback) para leer los resultados
let pruebas = sinPsql(readFileSync(join(server, 'tests/pruebas.sql'), 'utf8'));
const corte = pruebas.lastIndexOf('select n, case when ok');
pruebas = pruebas.slice(0, corte);
await aplicar('pruebas.sql', pruebas);
const { rows } = await db.query('select n, ok, prueba, detalle from resultado order by n');
const fallas = rows.filter((r) => !r.ok);
for (const r of fallas) console.log(`FALLA ${r.n}. ${r.prueba}: ${r.detalle}`);
console.log(`${rows.length - fallas.length} de ${rows.length} pruebas OK`);
await db.exec('rollback');
process.exit(fallas.length ? 1 : 0);
