#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

static void die(const char *label) {
  perror(label);
  _exit(127);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fputs("vt-ctty: missing command\n", stderr);
    return 127;
  }

  if (setsid() == -1) {
    die("setsid");
  }

#ifdef TIOCSCTTY
  if (ioctl(STDIN_FILENO, TIOCSCTTY, 0) == -1) {
    die("TIOCSCTTY");
  }
#endif

  if (tcsetpgrp(STDIN_FILENO, getpgrp()) == -1 && errno != ENOTTY) {
    die("tcsetpgrp");
  }

  execvp(argv[1], &argv[1]);
  die("execvp");
}
