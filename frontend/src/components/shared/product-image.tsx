import { useState } from 'react'
import { ImageIcon } from 'lucide-react'

type ImageProduct = { id: string; name: string; image_version?: string | null }
function productImageSource(product?: ImageProduct) {
  return product?.image_version ? `/api/v1/products/${product.id}/image?v=${product.image_version}` : undefined
}
export function ProductImage({ product, source, className = 'size-12' }: { product?: ImageProduct; source?: string; className?: string }) {
  const src = source ?? productImageSource(product)
  return <ImageContent key={src ?? 'empty'} src={src} name={product?.name ?? 'Product preview'} className={className} />
}
function ImageContent({ src, name, className }: { src?: string; name: string; className: string }) {
  const [failed, setFailed] = useState(false)
  return <span className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-lg border bg-white ${className}`}>
    {src && !failed ? <img src={src} alt={name} loading="lazy" decoding="async" className="h-full w-full object-contain" onError={() => setFailed(true)} /> : <ImageIcon aria-label="No product image" className="size-5 text-muted-foreground/50" />}
  </span>
}
