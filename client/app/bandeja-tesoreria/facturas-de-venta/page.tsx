import { redirect } from 'next/navigation';
import { RUTAS } from '@/lib/rutas';

export default function FacturasDeVenta() {
  redirect(RUTAS.ventas);
}
