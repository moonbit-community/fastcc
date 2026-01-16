// =====================================
// WARNING: very unstable API, for internal use only
// =====================================

#ifndef moonbit_h_INCLUDED
#define moonbit_h_INCLUDED

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
#include "moonbit-fundamental.h"
#else
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#if defined (_WIN32) || defined (_WIN64)
#ifdef MOONBIT_BUILD_RUNTIME
#define MOONBIT_EXPORT __declspec(dllexport)
#else
#ifdef MOONBIT_USE_SHARED_RUNTIME
#define MOONBIT_EXPORT __declspec(dllimport)
#else
#define MOONBIT_EXPORT
#endif
#endif
#define MOONBIT_FFI_EXPORT __declspec(dllexport)
#else
#define MOONBIT_EXPORT // __attribute__ ((visibility("default")))
#define MOONBIT_FFI_EXPORT
#endif

enum moonbit_block_kind {
  // 0 => regular block
  moonbit_BLOCK_KIND_REGULAR = 0,
  // 1 => array of pointers
  moonbit_BLOCK_KIND_REF_ARRAY = 1,
  // 2 => array of immediate value/string/bytes
  moonbit_BLOCK_KIND_VAL_ARRAY = 2,
  // 3 => external object with custom deallocator
  //   Note: if we run out of block kind in the future,
  //   we may turn [3] into [moonbit_BLOCK_KIND_EXTENDED],
  //   and store the actual kind & other meta information in the first field
  moonbit_BLOCK_KIND_EXTERNAL = 3
};

enum moonbit_ref_array_kind {
  // 1 => array of value types with reference fields
  moonbit_REF_ARRAY_REF_VALTYPE = 1,
  // for normal reference array, the value is currently
  // (sizeof(void*) >> 2) + 1
  // we could change it to a fixed value in the future
};

struct moonbit_object {
  int32_t rc;
  /* The layout of 32bit meta data (starting from most significant bit):

     enum moonbit_block_kind kind : 2;
     union {
       // when [kind = BLOCK_KIND_REGULAR]
       struct {
         // The 22 length bits are separated into two 11 bit parts:
         //
         // - [ptr_field_offset] is the offset of the first pointer field,
         //   counted by the number of 32-bit words.
         //   The object header itself is also included.
         //
         // - [n_ptr_fields] is the number of pointer fields
         //
         // We rearrange the layout of all pointer fields
         // so that all pointer fields are placed at the end.
         // This make it easy for the runtime to enumerate all pointer fields in an object,
         // without any static type information.
         //
         // The total length of the object can be reconstructed via:
         //
         //   ptr_field_offset * 4 + n_ptr_fields * sizeof(void*)
         unsigned int ptr_field_offset : 11;
         unsigned int n_ptr_fields : 11;
         // For blocks, we steal 8 bits from the length to represent enum tag
         unsigned int tag : 8;
       };
       // when [kind = BLOCK_KIND_REF_ARRAY] or [kind = BLOCK_KIND_VAL_ARRAY]
       struct {
         // The size of array element is [2^object_size_shift] bytes
         // For VAL_ARRAY, the size information is useless, and not precise when
         // the array elements are value types.
         // For REF_ARRAY, we use the following encoding currently:
         // 1 -> array of value type with reference fields
         // 2/3 -> array of references. Whether it's 2 or 3 depends on the platform.
         unsigned int object_size_shift : 2;
         // The number of elements
         unsigned int len : 28;
       } array_header;
       // when [kind = BLOCK_KIND_REF_EXTERN]
       uint32_t size : 30;
     };
  */
  uint32_t meta;
};

// For array of valtype-with-reference, there is an extra header
// before the normal array header. The extra header is used to store
// information for memory management on the valtype.
struct moonbit_valtype_array_header {
  uint32_t elem_header;
  uint32_t padding;
  struct moonbit_object array_header;
};

#define Moonbit_object_header(obj) ((struct moonbit_object*)(obj) - 1)
#define Moonbit_object_kind(obj) (Moonbit_object_header(obj)->meta >> 30)
#define Moonbit_object_tag(obj) (Moonbit_object_header(obj)->meta & 0xFF)
#define Moonbit_tag_from_header(header) (header & 0xFF)
#define Moonbit_array_length(obj) (Moonbit_object_header(obj)->meta & (((uint32_t)1 << 28) - 1))
#define Moonbit_array_elem_size_shift(obj) ((Moonbit_object_header(obj)->meta >> 28) & 3)
#define Moonbit_make_array_header(kind, elem_size_shift, length)\
  (((uint32_t)kind << 30)\
   | (((uint32_t)(elem_size_shift) & 3) << 28)\
   | ((length) & (((uint32_t)1 << 28) - 1)))
#define Moonbit_valtype_header(obj) ((struct moonbit_valtype_array_header*)(obj) - 1)

MOONBIT_EXPORT void *libc_malloc(size_t size);
MOONBIT_EXPORT void libc_free(void *ptr);
MOONBIT_EXPORT void *moonbit_malloc(size_t size);
MOONBIT_EXPORT void moonbit_incref(void *obj);
MOONBIT_EXPORT void moonbit_decref(void *obj);

typedef uint16_t *moonbit_string_t;
typedef uint8_t *moonbit_bytes_t;


MOONBIT_EXPORT moonbit_string_t moonbit_make_string(int32_t size, uint16_t value);
MOONBIT_EXPORT moonbit_string_t moonbit_make_string_raw(int32_t size);
MOONBIT_EXPORT moonbit_bytes_t moonbit_make_bytes(int32_t size, int value);
MOONBIT_EXPORT moonbit_bytes_t moonbit_make_bytes_raw(int32_t size);
MOONBIT_EXPORT int32_t *moonbit_make_int32_array(int32_t len, int32_t value);
MOONBIT_EXPORT int32_t *moonbit_make_int32_array_raw(int32_t len);
MOONBIT_EXPORT void **moonbit_make_ref_array(int32_t len, void *value);
MOONBIT_EXPORT void **moonbit_make_ref_array_raw(int32_t len);
MOONBIT_EXPORT int64_t *moonbit_make_int64_array(int32_t len, int64_t value);
MOONBIT_EXPORT int64_t *moonbit_make_int64_array_raw(int32_t len);
MOONBIT_EXPORT double *moonbit_make_double_array(int32_t len, double value);
MOONBIT_EXPORT double *moonbit_make_double_array_raw(int32_t len);
MOONBIT_EXPORT float *moonbit_make_float_array(int32_t len, float value);
MOONBIT_EXPORT float *moonbit_make_float_array_raw(int32_t len);
MOONBIT_EXPORT void **moonbit_make_extern_ref_array(int32_t len, void *value);
MOONBIT_EXPORT void **moonbit_make_extern_ref_array_raw(int32_t len);
MOONBIT_EXPORT void *moonbit_make_scalar_valtype_array(int32_t len, size_t valtype_size, void *init);
MOONBIT_EXPORT void *moonbit_make_ref_valtype_array(int32_t len, size_t valtype_size, uint32_t header, void *init);
MOONBIT_EXPORT void *moonbit_make_scalar_valtype_array_raw(int32_t len, size_t valtype_size);
MOONBIT_EXPORT void *moonbit_make_ref_valtype_array_raw(int32_t len, size_t valtype_size, uint32_t header);

/* `finalize` should drop the payload of the external object.
   `finalize` MUST NOT drop the [moonbit_external_object] container itself.

   `payload_size` is the size of payload, excluding [drop].

   The returned pointer points directly to the start of user payload.
   The finalizer pointer would be stored at the end of the object, after user payload.
*/
MOONBIT_EXPORT void *moonbit_make_external_object(
  void (*finalize)(void *self),
  uint32_t payload_size
);

MOONBIT_EXPORT void moonbit_update_ref_valtype_rc(int32_t len, void *value, uint32_t header);

MOONBIT_EXPORT extern uint8_t* const moonbit_empty_int8_array;
MOONBIT_EXPORT extern uint16_t* const moonbit_empty_int16_array;
MOONBIT_EXPORT extern int32_t* const moonbit_empty_int32_array;
MOONBIT_EXPORT extern int64_t* const moonbit_empty_int64_array;
MOONBIT_EXPORT extern float*   const moonbit_empty_float_array;
MOONBIT_EXPORT extern double*  const moonbit_empty_double_array;
MOONBIT_EXPORT extern void**   const moonbit_empty_ref_array;
MOONBIT_EXPORT extern void**   const moonbit_empty_extern_ref_array;
MOONBIT_EXPORT extern void* const moonbit_empty_scalar_valtype_array;
MOONBIT_EXPORT extern void* const moonbit_empty_ref_valtype_array;

// ----------------------------------------------------------------------------
// byte-swap and extraction functions
// ----------------------------------------------------------------------------

#ifndef __has_builtin
#  define __has_builtin(x) 0
#endif

#if __has_builtin(__builtin_bswap64)
#  define BSWAP64(x) __builtin_bswap64((uint64_t)(x))
#  define BSWAP32(x) __builtin_bswap32((uint32_t)(x))
#elif defined(_MSC_VER)
#  include <stdlib.h>
#  define BSWAP64(x) _byteswap_uint64((uint64_t)(x))
#  define BSWAP32(x) _byteswap_ulong((uint32_t)(x))
#else
#  define BSWAP64(x) ( \
      (((uint64_t)(x) & 0x00000000000000FFULL) << 56) | \
      (((uint64_t)(x) & 0x000000000000FF00ULL) << 40) | \
      (((uint64_t)(x) & 0x0000000000FF0000ULL) << 24) | \
      (((uint64_t)(x) & 0x00000000FF000000ULL) <<  8) | \
      (((uint64_t)(x) & 0x000000FF00000000ULL) >>  8) | \
      (((uint64_t)(x) & 0x0000FF0000000000ULL) >> 24) | \
      (((uint64_t)(x) & 0x00FF000000000000ULL) >> 40) | \
      (((uint64_t)(x) & 0xFF00000000000000ULL) >> 56))
#  define BSWAP32(x) ( \
      (((uint32_t)(x) & 0x000000FFU) << 24) | \
      (((uint32_t)(x) & 0x0000FF00U) <<  8) | \
      (((uint32_t)(x) & 0x00FF0000U) >>  8) | \
      (((uint32_t)(x) & 0xFF000000U) >> 24))
#endif

#define BSWAP16(x) ( \
  (((uint16_t)(x) & 0x00FFU) << 8) | \
  (((uint16_t)(x) & 0xFF00U) >> 8))

// Detect if we're on x86 or ARMv6+
#if defined(__x86_64__) || defined(_M_X64) || defined(__amd64__) || \
    defined(__i386__) || defined(_M_IX86) || \
    defined(__aarch64__) || defined(_M_ARM64) || \
    (defined(__ARM_ARCH) && __ARM_ARCH >= 6)
    #define SUPPORTS_UNALIGNED_ACCESS 1
#else
    #define SUPPORTS_UNALIGNED_ACCESS 0
#endif  

#if SUPPORTS_UNALIGNED_ACCESS
    // Fast path: direct memory access
    #define READ_UINT64(ptr) (*(const uint64_t*)(ptr))
    #define READ_UINT32(ptr) (*(const uint32_t*)(ptr))
    #define READ_UINT16(ptr) (*(const uint16_t*)(ptr))
    #define WRITE_UINT64(ptr, value) (*(uint64_t*)(ptr) = (value))
    #define WRITE_UINT32(ptr, value) (*(uint32_t*)(ptr) = (value))
    #define WRITE_UINT16(ptr, value) (*(uint16_t*)(ptr) = (value))
#else
    // Safe path: use memcpy (prevents crashes on ARMv5 and earlier)
    static inline uint64_t read_uint64_unaligned(const void* ptr) {
        uint64_t value;
        memcpy(&value, ptr, sizeof(uint64_t));
        return value;
    }
    
    static inline uint32_t read_uint32_unaligned(const void* ptr) {
        uint32_t value;
        memcpy(&value, ptr, sizeof(uint32_t));
        return value;
    }
    
    static inline uint16_t read_uint16_unaligned(const void* ptr) {
        uint16_t value;
        memcpy(&value, ptr, sizeof(uint16_t));
        return value;
    }
    
    static inline void write_uint64_unaligned(void* ptr, uint64_t value) {
        memcpy(ptr, &value, sizeof(uint64_t));
    }
    
    static inline void write_uint32_unaligned(void* ptr, uint32_t value) {
        memcpy(ptr, &value, sizeof(uint32_t));
    }
    
    static inline void write_uint16_unaligned(void* ptr, uint16_t value) {
        memcpy(ptr, &value, sizeof(uint16_t));
    }
    
    #define READ_UINT64(ptr) read_uint64_unaligned(ptr)
    #define READ_UINT32(ptr) read_uint32_unaligned(ptr)
    #define READ_UINT16(ptr) read_uint16_unaligned(ptr)
    #define WRITE_UINT64(ptr, value) write_uint64_unaligned(ptr, value)
    #define WRITE_UINT32(ptr, value) write_uint32_unaligned(ptr, value)
    #define WRITE_UINT16(ptr, value) write_uint16_unaligned(ptr, value)
#endif

#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && defined(__ORDER_LITTLE_ENDIAN__)
#  define HOST_BIG_ENDIAN (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#else
  /* Fallback runtime test (rarely needed) */
#  define HOST_BIG_ENDIAN (!*(unsigned char *)&(uint16_t){1})
#endif

#define READ_UINT64_LE(ptr) (HOST_BIG_ENDIAN ? BSWAP64(READ_UINT64(ptr)) : READ_UINT64(ptr))
#define READ_UINT32_LE(ptr) (HOST_BIG_ENDIAN ? BSWAP32(READ_UINT32(ptr)) : READ_UINT32(ptr))
#define READ_UINT64_BE(ptr) (HOST_BIG_ENDIAN ? READ_UINT64(ptr) : BSWAP64(READ_UINT64(ptr)))
#define READ_UINT32_BE(ptr) (HOST_BIG_ENDIAN ? READ_UINT32(ptr) : BSWAP32(READ_UINT32(ptr)))
#define READ_UINT16_LE(ptr) (HOST_BIG_ENDIAN ? BSWAP16(READ_UINT16(ptr)) : READ_UINT16(ptr))
#define READ_UINT16_BE(ptr) (HOST_BIG_ENDIAN ? READ_UINT16(ptr) : BSWAP16(READ_UINT16(ptr)))
#define WRITE_UINT64_LE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT64(ptr, BSWAP64(value)) : WRITE_UINT64(ptr, value))
#define WRITE_UINT32_LE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT32(ptr, BSWAP32(value)) : WRITE_UINT32(ptr, value))
#define WRITE_UINT64_BE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT64(ptr, value) : WRITE_UINT64(ptr, BSWAP64(value)))
#define WRITE_UINT32_BE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT32(ptr, value) : WRITE_UINT32(ptr, BSWAP32(value)))
#define WRITE_UINT16_LE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT16(ptr, BSWAP16(value)) : WRITE_UINT16(ptr, value))
#define WRITE_UINT16_BE(ptr, value) (HOST_BIG_ENDIAN ? WRITE_UINT16(ptr, value) : WRITE_UINT16(ptr, BSWAP16(value)))

#ifdef __cplusplus
}
#endif

#endif // moonbit_h_INCLUDED
