import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

/** true cuando faltan las variables de entorno de Supabase (ver client/.env.example). */
export const faltaConfiguracion = !url || !anonKey;

export const supabase: SupabaseClient | null = faltaConfiguracion
  ? null
  : createClient(url!, anonKey!, { auth: { persistSession: true, autoRefreshToken: true } });

/** Bucket privado donde se guardan las imágenes y PDF de las facturas de compra. */
export const BUCKET_COMPROBANTES = 'comprobantes';

/** Supabase Auth pide un mail: cada usuario del equipo tiene uno interno que nunca recibe nada. */
export const DOMINIO_USUARIOS = 'equipo.motorespesados';
export const mailDeUsuario = (usuario: string) => `${usuario.trim().toLowerCase()}@${DOMINIO_USUARIOS}`;
export const usuarioDeMail = (mail?: string | null) => (mail ?? '').split('@')[0];
