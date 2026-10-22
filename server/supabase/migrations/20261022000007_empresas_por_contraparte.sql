-- Clientes y proveedores son comunes a las dos empresas. La lista informa
-- con qué empresas operó cada uno (comprobantes no borrador: ventas para
-- clientes, compras para proveedores), para mostrarlo en la tarjeta.
create or replace function public.listar_contrapartes(p_tipo text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
      'documento', case when c.tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(c.numero_doc) end,
      'condicion_desc', (select ci.descripcion from fiscal.condicion_iva ci where ci.codigo = c.condicion_iva),
      'faltantes', to_jsonb(fiscal.faltantes(c)),
      'completo', cardinality(fiscal.faltantes(c)) = 0
        and (not c.es_proveedor or p_tipo = 'cliente' or c.tipo_doc = 80),
      'empresas', coalesce((select jsonb_agg(distinct k.empresa_id order by k.empresa_id) from fiscal.comprobante k
        where k.contraparte_id = c.id and k.estado <> 'borrador'
          and (p_tipo is null or k.operacion = case p_tipo when 'cliente' then 'venta' else 'compra' end)), '[]'::jsonb))
    order by c.nombre), '[]'::jsonb)
  from fiscal.contraparte c
  where p_tipo is null or (p_tipo = 'cliente' and c.es_cliente) or (p_tipo = 'proveedor' and c.es_proveedor)
$$;
