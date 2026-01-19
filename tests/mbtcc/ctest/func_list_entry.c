#include <stdio.h>

typedef unsigned char uint8_t;
typedef short int16_t;
typedef int int32_t;
typedef long long int64_t;

typedef struct JSContext JSContext;
typedef int JSValue;
typedef JSValue (JSCFunction)(JSContext *, JSValue, int, JSValue *);

typedef union JSCFunctionType {
  JSCFunction *generic;
  JSValue (*generic_magic)(JSContext *, JSValue, int, JSValue *, int);
  JSCFunction *constructor;
  JSValue (*constructor_magic)(JSContext *, JSValue, int, JSValue *, int);
  JSCFunction *constructor_or_func;
  double (*f_f)(double);
  double (*f_f_f)(double, double);
  JSValue (*getter)(JSContext *, JSValue);
  JSValue (*setter)(JSContext *, JSValue, JSValue);
  JSValue (*getter_magic)(JSContext *, JSValue, int);
  JSValue (*setter_magic)(JSContext *, JSValue, JSValue, int);
  JSValue (*iterator_next)(JSContext *, JSValue, int, JSValue *, int *, int);
} JSCFunctionType;

typedef struct JSCFunctionListEntry {
  const char *name;
  uint8_t prop_flags;
  uint8_t def_type;
  int16_t magic;
  union {
    struct {
      uint8_t length;
      uint8_t cproto;
      JSCFunctionType cfunc;
    } func;
    const char *str;
    int32_t i32;
    int64_t i64;
    double f64;
  } u;
} JSCFunctionListEntry;

static JSValue test_func(JSContext *ctx, JSValue this_val, int argc, JSValue *argv) {
  (void)ctx;
  (void)this_val;
  (void)argc;
  (void)argv;
  return 0;
}

static const JSCFunctionListEntry entry = {
  "foo",
  3,
  0,
  7,
  .u = { .func = { 2, 1, { .generic = test_func } } },
};

int main(void) {
  printf("%d\n", entry.u.func.cfunc.generic == test_func);
  printf("%u %u %d %u %u\n",
         (unsigned)entry.prop_flags,
         (unsigned)entry.def_type,
         (int)entry.magic,
         (unsigned)entry.u.func.length,
         (unsigned)entry.u.func.cproto);
  return 0;
}
