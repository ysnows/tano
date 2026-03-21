import { watch, type FSWatcher } from "fs";
import { relative, extname } from "path";

export interface WatcherOptions {
    dirs: string[];
    extensions: string[];
    ignore: string[];
    onChange: (path: string, event: string) => void;
    debounceMs?: number;
}

export function startWatcher(options: WatcherOptions): () => void {
    const {
        dirs,
        extensions,
        ignore = ["node_modules", "dist", ".git"],
        onChange,
        debounceMs = 100,
    } = options;

    const watchers: FSWatcher[] = [];
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const pendingChanges = new Map<string, string>();

    function shouldIgnore(filePath: string): boolean {
        return ignore.some((pattern) => filePath.includes(pattern));
    }

    function hasValidExtension(filePath: string): boolean {
        if (extensions.length === 0) return true;
        const ext = extname(filePath);
        return extensions.includes(ext);
    }

    function flushChanges(): void {
        for (const [path, event] of pendingChanges) {
            onChange(path, event);
        }
        pendingChanges.clear();
    }

    for (const dir of dirs) {
        try {
            const watcher = watch(dir, { recursive: true }, (event, filename) => {
                if (!filename) return;

                const filePath = `${dir}/${filename}`;
                const relativePath = relative(process.cwd(), filePath);

                if (shouldIgnore(relativePath)) return;
                if (!hasValidExtension(relativePath)) return;

                pendingChanges.set(relativePath, event);

                if (debounceTimer) {
                    clearTimeout(debounceTimer);
                }
                debounceTimer = setTimeout(flushChanges, debounceMs);
            });

            watchers.push(watcher);
        } catch {
            // Directory may not exist yet, skip silently
        }
    }

    return () => {
        if (debounceTimer) {
            clearTimeout(debounceTimer);
        }
        for (const watcher of watchers) {
            watcher.close();
        }
    };
}
