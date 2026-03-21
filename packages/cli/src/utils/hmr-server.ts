import type { ServerWebSocket } from "bun";

interface HMRMessage {
    type: "reload" | "css" | "server";
    path?: string;
}

export function startHMRServer(port: number): {
    notify: (type: HMRMessage["type"], path?: string) => void;
    stop: () => void;
} {
    const clients = new Set<ServerWebSocket<unknown>>();

    const server = Bun.serve({
        port,
        fetch(req, server) {
            if (server.upgrade(req)) {
                return undefined;
            }
            return new Response("Tano HMR server");
        },
        websocket: {
            open(ws) {
                clients.add(ws);
            },
            message(ws, msg) {
                // Handle ping/pong to keep connection alive
                if (msg === "ping") {
                    ws.send("pong");
                }
            },
            close(ws) {
                clients.delete(ws);
            },
        },
    });

    return {
        notify(type: HMRMessage["type"], path?: string) {
            const message = JSON.stringify({ type, path });
            for (const client of clients) {
                try {
                    client.send(message);
                } catch {
                    clients.delete(client);
                }
            }
        },
        stop() {
            server.stop();
        },
    };
}
