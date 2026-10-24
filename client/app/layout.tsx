import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import './globals.css';
import { ProveedorApp } from '@/lib/contexto';
import { Shell } from '@/components/Shell';

export const metadata: Metadata = {
  title: 'Motores Pesados · Libro de IVA',
  description: 'Prototipo 1.0: facturas de compra y de venta, libro de IVA y posición. Datos inventados.',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="es-AR" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;700&display=swap" />
      </head>
      <body>
        <ProveedorApp>
          <Shell>{children}</Shell>
        </ProveedorApp>
      </body>
    </html>
  );
}
