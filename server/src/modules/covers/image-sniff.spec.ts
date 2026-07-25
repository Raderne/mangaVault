import { extForMime, mimeForExt, sniffImage } from './image-sniff';

const pad = (head: number[]): Buffer =>
  Buffer.concat([Buffer.from(head), Buffer.alloc(16)]);

describe('sniffImage', () => {
  it('detects JPEG', () => {
    expect(sniffImage(pad([0xff, 0xd8, 0xff, 0xe0]))).toEqual({
      mime: 'image/jpeg',
      ext: 'jpg',
    });
  });

  it('detects PNG', () => {
    expect(
      sniffImage(pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
    ).toEqual({ mime: 'image/png', ext: 'png' });
  });

  it('detects GIF', () => {
    expect(sniffImage(pad([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))).toEqual({
      mime: 'image/gif',
      ext: 'gif',
    });
  });

  it('detects WEBP (RIFF….WEBP)', () => {
    const bytes = Buffer.from('RIFF\0\0\0\0WEBPVP8 ', 'ascii');
    expect(sniffImage(bytes)).toEqual({ mime: 'image/webp', ext: 'webp' });
  });

  it('detects AVIF (ftyp/avif brand)', () => {
    const bytes = Buffer.from('\0\0\0\x20ftypavif', 'ascii');
    expect(sniffImage(bytes)).toEqual({ mime: 'image/avif', ext: 'avif' });
  });

  it('rejects non-images and short buffers', () => {
    expect(sniffImage(Buffer.from('<!DOCTYPE html><html></html>'))).toBeNull();
    expect(sniffImage(Buffer.from([0xff, 0xd8]))).toBeNull(); // too short
  });
});

describe('mime/ext mapping', () => {
  it('maps mime → ext, tolerating parameters and case', () => {
    expect(extForMime('image/jpeg')).toBe('jpg');
    expect(extForMime('IMAGE/PNG; charset=binary')).toBe('png');
    expect(extForMime('text/html')).toBe('bin');
  });

  it('maps ext → mime, tolerating leading dot', () => {
    expect(mimeForExt('jpg')).toBe('image/jpeg');
    expect(mimeForExt('.webp')).toBe('image/webp');
    expect(mimeForExt('xyz')).toBe('application/octet-stream');
  });
});
