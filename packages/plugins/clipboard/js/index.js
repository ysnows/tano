async function invoke(method, params) {
    if (typeof window !== 'undefined' && window.Tano) {
        return window.Tano.invoke('clipboard', method, params || {});
    }
    throw new Error('Tano bridge not available.');
}

export async function copy(text) {
    return invoke('copy', { text });
}

export async function read() {
    return invoke('read', {});
}
