export function hash(algorithm: 'sha256' | 'sha384' | 'sha512', data: string): Promise<string>;
export function hmac(algorithm: 'sha256' | 'sha384' | 'sha512', key: string, data: string): Promise<string>;
export function randomUUID(): Promise<string>;
export function randomBytes(length: number): Promise<string>;
export interface EncryptResult { ciphertext: string; iv: string; tag: string; }
export function encrypt(key: string, data: string, iv?: string): Promise<EncryptResult>;
export function decrypt(key: string, ciphertext: string, iv: string, tag: string): Promise<string>;
