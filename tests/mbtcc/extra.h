#ifndef TINYCC_MBT_MBTCC_EXTRA_H
#define TINYCC_MBT_MBTCC_EXTRA_H

// mbtcc's ctest2 suite intentionally avoids system headers and provides a
// minimal "test.h". Some tests still rely on NULL/strlen without declarations.
// Provide them here so both gcc and tinycc.mbt compile the suite consistently.

#ifndef NULL
#define NULL 0
#endif

unsigned long strlen(const char* s);

#endif

