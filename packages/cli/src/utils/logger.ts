// ANSI color codes for terminal output

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";

const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const CYAN = "\x1b[36m";

export const log = {
    info(message: string): void {
        console.log(message);
    },

    success(message: string): void {
        console.log(`${GREEN}${BOLD}✓${RESET} ${message}`);
    },

    warn(message: string): void {
        console.log(`${YELLOW}${BOLD}⚠${RESET} ${YELLOW}${message}${RESET}`);
    },

    error(message: string): void {
        console.error(`${RED}${BOLD}✗${RESET} ${RED}${message}${RESET}`);
    },

    step(message: string): void {
        console.log(`${CYAN}${BOLD}→${RESET} ${message}`);
    },

    dim(message: string): void {
        console.log(`${DIM}${message}${RESET}`);
    },

    heading(message: string): void {
        console.log(`\n${BLUE}${BOLD}${message}${RESET}`);
    },

    check(label: string, ok: boolean, detail?: string): void {
        const icon = ok ? `${GREEN}✓${RESET}` : `${RED}✗${RESET}`;
        const suffix = detail ? ` ${DIM}(${detail})${RESET}` : "";
        console.log(`  ${icon} ${label}${suffix}`);
    },
};
