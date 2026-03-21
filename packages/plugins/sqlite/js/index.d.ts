export interface RunResult {
    changes: number;
    lastInsertRowId: number;
}

export function open(path: string): Promise<string>;
export function query<T = Record<string, any>>(handle: string, sql: string, params?: any[]): Promise<T[]>;
export function run(handle: string, sql: string, params?: any[]): Promise<RunResult>;
export function close(handle: string): Promise<void>;
