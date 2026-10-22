-- =====================================================================
-- Imágenes y PDF de las facturas de compra (Supabase Storage).
-- Bucket privado "comprobantes": el front sube el archivo y guarda la
-- ruta en el comprobante; para verlo pide una URL firmada.
-- Sin login en esta versión, así que el rol anon puede subir y leer,
-- pero no reemplazar ni borrar (el respaldo de una factura no se toca).
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprobantes', 'comprobantes', false, 10485760, array['image/png', 'image/jpeg', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

create policy "comprobantes: subir" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'comprobantes');

create policy "comprobantes: ver" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'comprobantes');
