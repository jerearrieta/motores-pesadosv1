import type { NextConfig } from 'next';

// Las rutas anteriores al traslado a «Bandeja Tesorería» siguen funcionando: redirigen a la pestaña nueva.
const B = '/bandeja-tesoreria';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  redirects() {
    return Promise.resolve([
      { source: '/libro', destination: `${B}/libro-de-iva/libro-y-posicion`, permanent: false },
      { source: '/cierre', destination: `${B}/libro-de-iva/cierre-e-historial`, permanent: false },
      { source: '/ventas', destination: `${B}/facturas-de-venta/facturas-emitidas`, permanent: false },
      { source: '/ventas/:resto*', destination: `${B}/facturas-de-venta/facturas-emitidas/:resto*`, permanent: false },
      { source: '/compras', destination: `${B}/facturas-de-compra`, permanent: false },
      { source: '/compras/nueva', destination: `${B}/facturas-de-compra/cargar-factura-de-compra`, permanent: false },
      { source: '/compras/:id', destination: `${B}/facturas-de-compra/:id`, permanent: false },
    ]);
  },
};

export default nextConfig;
