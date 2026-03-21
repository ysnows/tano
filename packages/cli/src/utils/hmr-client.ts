export function getHMRClientScript(port: number): string {
    return `
<script>
(function() {
    var ws = new WebSocket('ws://127.0.0.1:${port}/');
    ws.onmessage = function(e) {
        var msg = JSON.parse(e.data);
        if (msg.type === 'reload' || msg.type === 'server') {
            console.log('[Tano HMR] Reloading...');
            location.reload();
        }
        if (msg.type === 'css') {
            console.log('[Tano HMR] CSS update');
            document.querySelectorAll('link[rel="stylesheet"]').forEach(function(link) {
                link.href = link.href.split('?')[0] + '?t=' + Date.now();
            });
        }
    };
    ws.onopen = function() {
        console.log('[Tano HMR] Connected');
    };
    ws.onclose = function() {
        console.log('[Tano HMR] Disconnected, retrying...');
        setTimeout(function() { location.reload(); }, 2000);
    };
})();
</script>`;
}
