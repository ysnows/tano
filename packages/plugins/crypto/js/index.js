async function invoke(method, params) {
    if (typeof window !== 'undefined' && window.Tano) {
        return window.Tano.invoke('crypto', method, params || {});
    }
    throw new Error('Tano bridge not available.');
}

export async function hash(algorithm, data) {
    return invoke('hash', { algorithm, data });
}

export async function hmac(algorithm, key, data) {
    return invoke('hmac', { algorithm, key, data });
}

export async function randomUUID() {
    return invoke('randomUUID', {});
}

export async function randomBytes(length) {
    return invoke('randomBytes', { length });
}

export async function encrypt(key, data, iv) {
    const params = { key, data };
    if (iv) params.iv = iv;
    return invoke('encrypt', params);
}

export async function decrypt(key, ciphertext, iv, tag) {
    return invoke('decrypt', { key, ciphertext, iv, tag });
}
