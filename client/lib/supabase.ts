import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

/** true cuando faltan las variables de entorno de Supabase (ver client/.env.example). */
export const faltaConfiguracion = !url || !anonKey;

export const supabase: SupabaseClient | null = faltaConfiguracion
  ? null
  : createClient(url!, anonKey!, { auth: { persistSession: false } });

/** Bucket privado donde se guardan las imágenes y PDF de las facturas de compra. */
export const BUCKET_COMPROBANTES = 'comprobantes';
