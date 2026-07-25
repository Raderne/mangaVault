import { ContainerDetector } from './detect';

describe('ContainerDetector', () => {
  const d = new ContainerDetector();

  it('detects gzip magic', () => {
    expect(d.detect(new Uint8Array([0x1f, 0x8b, 0x08, 0x00]))).toBe(
      'gzip-proto',
    );
  });

  it('detects legacy JSON by leading brace', () => {
    expect(d.detect(new Uint8Array([0x7b, 0x22]))).toBe('legacy-json'); // {"
  });

  it('detects legacy JSON past whitespace and BOM', () => {
    expect(d.detect(new Uint8Array([0xef, 0xbb, 0xbf, 0x0a, 0x20, 0x7b]))).toBe(
      'legacy-json',
    );
  });

  it('falls back to raw protobuf', () => {
    expect(d.detect(new Uint8Array([0x0a, 0x05, 0x08, 0x01]))).toBe(
      'raw-proto',
    );
  });
});
