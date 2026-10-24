'use client';

import { Cabecera, useEmpresa } from '@/components/ui';
import { ConciliacionArca } from '@/components/ConciliacionArca';

export default function Conciliacion() {
  const emp = useEmpresa();
  return (
    <>
      <Cabecera icono="conciliar" titulo="Conciliación con ARCA"
        bajada={<>Compará las compras y las ventas de {emp.razon_social} con «Mis Comprobantes» de ARCA antes de cerrar el mes.</>} />
      <ConciliacionArca />
    </>
  );
}
