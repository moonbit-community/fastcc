#ifndef _TCC_COMPAT_TERMIOS_H
#define _TCC_COMPAT_TERMIOS_H

#include <sys/types.h>

typedef unsigned int tcflag_t;
typedef unsigned char cc_t;
typedef unsigned int speed_t;

#ifndef NCCS
#define NCCS 32
#endif

struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t c_cc[NCCS];
  speed_t c_ispeed;
  speed_t c_ospeed;
};

#define TCSANOW 0
#define TCSADRAIN 1
#define TCSAFLUSH 2

#define IGNBRK  0x00000001
#define BRKINT  0x00000002
#define PARMRK  0x00000008
#define ISTRIP  0x00000020
#define INLCR   0x00000040
#define IGNCR   0x00000080
#define ICRNL   0x00000100
#define IXON    0x00000200

#define OPOST   0x00000001

#define ICANON 0x0002
#define ECHO 0x0008
#define ISIG 0x0001
#define ECHONL 0x00000010
#define IEXTEN 0x00000400

#define CSIZE  0x00000300
#define PARENB 0x00001000
#define CS8    0x00000300

#define VMIN  16
#define VTIME 17

int tcgetattr(int fd, struct termios *termios_p);
int tcsetattr(int fd, int optional_actions, const struct termios *termios_p);
int tcflush(int fd, int queue_selector);
speed_t cfgetispeed(const struct termios *termios_p);
speed_t cfgetospeed(const struct termios *termios_p);
int cfsetispeed(struct termios *termios_p, speed_t speed);
int cfsetospeed(struct termios *termios_p, speed_t speed);
int cfmakeraw(struct termios *termios_p);

#endif /* _TCC_COMPAT_TERMIOS_H */
