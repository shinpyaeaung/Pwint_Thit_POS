// Leave headroom below the server storage limit for its sanitizing re-encode.
const targetBytes = 1024 * 1024

// Resize before upload so camera photos fit both the API's pixel and byte limits.
// Canvas applies the browser's photo orientation and retains PNG transparency.
export async function prepareProductImage(file: File): Promise<File> {
  if (!['image/jpeg', 'image/png'].includes(file.type) || !file.size) throw new Error('Choose a JPEG or PNG image.')
  if (file.size > 50 * 1024 * 1024) throw new Error('Choose an image up to 50 MB for automatic compression.')
  const url = URL.createObjectURL(file)
  try {
    const image = new Image()
    image.src = url
    try { await image.decode() } catch { throw new Error('This image could not be opened. Choose another JPEG or PNG.') }
    const scale = Math.min(1, 2048 / Math.max(image.naturalWidth, image.naturalHeight))
    let width = Math.max(1, Math.round(image.naturalWidth * scale))
    let height = Math.max(1, Math.round(image.naturalHeight * scale))
    const canvas = document.createElement('canvas')
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Image processing is unavailable. Please try another browser.')
    for (;;) {
      canvas.width = width
      canvas.height = height
      context.imageSmoothingEnabled = true
      context.imageSmoothingQuality = 'high'
      context.drawImage(image, 0, 0, width, height)
      const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Unable to compress this image. Choose another file.')), file.type, 0.85))
      if (blob.size <= targetBytes) return new File([blob], file.name, { type: blob.type })
      if (width === 1 && height === 1) throw new Error('Unable to compress this image. Choose another file.')
      width = Math.max(1, Math.floor(width * 0.75))
      height = Math.max(1, Math.floor(height * 0.75))
    }
  } finally {
    URL.revokeObjectURL(url)
  }
}
