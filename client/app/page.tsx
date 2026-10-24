import { redirect } from 'next/navigation';
import { RUTAS } from '@/lib/rutas';

export default function Inicio() {
  redirect(RUTAS.libro);
}
