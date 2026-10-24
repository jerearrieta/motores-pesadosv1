'use client';

import { SeccionesCompra } from '@/components/Bandeja';
import { Cabecera, useEmpresa } from '@/components/ui';
import { ConciliacionArca } from '@/components/ConciliacionArca';

export default function ImportarDesdeArca() {
  const emp = useEmpresa();
  return (
    <>
      <Cabecera icono="carro" titulo="Facturas de compra"
        bajada={<>Comprobantes de proveedores de {emp.razon_social}: alimentan el crédito fiscal del libro de compras.</>} />
      <SeccionesCompra />
      <ConciliacionArca tipoFijo="recibidos" />
    </>
  );
}
