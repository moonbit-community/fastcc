#ifndef moonbit_fundamental_h_INCLUDED
#define moonbit_fundamental_h_INCLUDED
typedef __SIZE_TYPE__ size_t;
typedef __UINTPTR_TYPE__ uintptr_t;

typedef __INT32_TYPE__ int32_t;
typedef unsigned __INT32_TYPE__ uint32_t;

typedef __INT64_TYPE__ int64_t;
typedef unsigned __INT64_TYPE__ uint64_t;

typedef short int16_t; 
typedef unsigned short uint16_t; 
typedef unsigned char uint8_t;

#define INFINITY (1.0/0.0)
#define NAN (0.0/0.0)
#define offsetof(type, field) ((uintptr_t)(&(((type*)0)->field)))
#endif
