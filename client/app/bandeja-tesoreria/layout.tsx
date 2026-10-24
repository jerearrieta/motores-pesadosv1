import type { ReactNode } from 'react';
import { Bandeja } from '@/components/Bandeja';

export default function LayoutBandeja({ children }: { children: ReactNode }) {
  return <Bandeja>{children}</Bandeja>;
}
