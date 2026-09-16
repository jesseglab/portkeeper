#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fputs("Portkeeper runner: expected folder and command\n", stderr);
        return 64;
    }
    // Foundation's Process may already start us as a process-group leader.
    // In that case setsid() returns EPERM, but the group is already isolated
    // for Portkeeper's stop action.
    if (setsid() < 0 && getpgrp() != getpid()) {
        fprintf(stderr, "Portkeeper runner: process group: %s\n", strerror(errno));
        return 1;
    }
    if (chdir(argv[1]) < 0) {
        fprintf(stderr, "Portkeeper runner: folder: %s\n", strerror(errno));
        return 1;
    }
    // Load the user's toolchain without interactive job control, keeping npm,
    // Vite, and their children in this runner's private process group.
    const char *prefix = "source ~/.zshrc; if typeset -f nvm >/dev/null 2>&1; then nvm use --silent >/dev/null 2>&1 || true; fi; ";
    char *script = malloc(strlen(prefix) + strlen(argv[2]) + 1);
    if (!script) return 1;
    strcpy(script, prefix);
    strcat(script, argv[2]);
    execl("/bin/zsh", "zsh", "-lc", script, (char *)NULL);
    fprintf(stderr, "Portkeeper runner: shell: %s\n", strerror(errno));
    return 1;
}
