async function invoke(method, params) {
    if (typeof window !== 'undefined' && window.Tano) {
        return window.Tano.invoke('sqlite', method, params || {});
    }
    throw new Error('Tano bridge not available. Are you running inside a Tano app?');
}

export async function open(path) {
    return invoke('open', { path });
}

export async function query(handle, sql, params) {
    return invoke('query', { handle, sql, params: params || [] });
}

export async function run(handle, sql, params) {
    return invoke('run', { handle, sql, params: params || [] });
}

export async function close(handle) {
    return invoke('close', { handle });
}
