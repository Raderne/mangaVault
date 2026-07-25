/**
 * Tiny image content sniffer — maps magic bytes to a MIME type + file
 * extension. Used to decide the on-disk name of an archived cover and the
 * `Content-Type` served back, independent of what (if any) header a remote
 * host claimed. Returns `null` for anything we don't recognise as an image.
 */
export interface SniffedImage {
  mime: string;
  ext: string;
}

const ascii = (bytes: Uint8Array, start: number, text: string): boolean => {
  for (let i = 0; i < text.length; i++) {
    if (bytes[start + i] !== text.charCodeAt(i)) return false;
  }
  return true;
};

/** Detect a raster image from its leading bytes. */
export function sniffImage(bytes: Uint8Array): SniffedImage | null {
  if (bytes.length < 12) return null;

  // JPEG: FF D8 FF
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { mime: 'image/jpeg', ext: 'jpg' };
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47
  ) {
    return { mime: 'image/png', ext: 'png' };
  }
  // GIF: "GIF8"
  if (ascii(bytes, 0, 'GIF8')) {
    return { mime: 'image/gif', ext: 'gif' };
  }
  // WEBP: "RIFF" .... "WEBP"
  if (ascii(bytes, 0, 'RIFF') && ascii(bytes, 8, 'WEBP')) {
    return { mime: 'image/webp', ext: 'webp' };
  }
  // AVIF/HEIF: box "ftyp" at offset 4 with an avif/heic brand.
  if (ascii(bytes, 4, 'ftyp')) {
    if (ascii(bytes, 8, 'avif') || ascii(bytes, 8, 'avis')) {
      return { mime: 'image/avif', ext: 'avif' };
    }
    if (ascii(bytes, 8, 'heic') || ascii(bytes, 8, 'heix')) {
      return { mime: 'image/heic', ext: 'heic' };
    }
  }
  // BMP: "BM"
  if (bytes[0] === 0x42 && bytes[1] === 0x4d) {
    return { mime: 'image/bmp', ext: 'bmp' };
  }
  return null;
}

/** MIME → file extension for the formats we serve (fallback: `bin`). */
export function extForMime(mime: string): string {
  switch (mime.split(';')[0].trim().toLowerCase()) {
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/gif':
      return 'gif';
    case 'image/webp':
      return 'webp';
    case 'image/avif':
      return 'avif';
    case 'image/heic':
    case 'image/heif':
      return 'heic';
    case 'image/bmp':
      return 'bmp';
    default:
      return 'bin';
  }
}

/** MIME for a known cover extension (fallback: octet-stream). */
export function mimeForExt(ext: string): string {
  switch (ext.replace(/^\./, '').toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'avif':
      return 'image/avif';
    case 'heic':
    case 'heif':
      return 'image/heic';
    case 'bmp':
      return 'image/bmp';
    default:
      return 'application/octet-stream';
  }
}
