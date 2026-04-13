#define _GNU_SOURCE
#include <sys/mount.h>
#include <stdio.h>

int main() {
    if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) == -1) {
        perror("mount");
        return 1;
    }
    return 0;
}
