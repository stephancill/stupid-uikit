// swiftcorepatch.c -- the stdlib entry points our COMPILER emits and the
// STAGED RUNTIME does not have.
//
// This is a structural mismatch, not a one-off: swiftc here is 6.2.x, while
// libswiftCore.dylib is Apple's shipped simulator runtime from an older
// toolchain (docs/RUNTIME.md §4). Anything the newer compiler emits a direct
// call to, the older runtime may simply lack. Expect this file to grow, and
// keep each entry documented with what emits it.
//
// THE SYSROOT DOES NOT WARN YOU. libswiftCore.tbd ADVERTISES
// _stdlib_isOSVersionAtLeastOrVariantVersion, so the link is clean and the
// failure is deferred to load time in the guest -- the same .tbd-disagrees-with-
// dylib class as pthread_main_np, but inverted (there the .tbd advertised too
// little; here it advertises too much).
//
// ---- _stdlib_isOSVersionAtLeastOrVariantVersion ----------------------------
// EMITTED BY: swift_task_deinitOnExecutorMainActorBackDeploy, the
// back-deployment thunk the compiler generates for a @MainActor-ISOLATED
// deinit. ~/uikit gained those when M15 put the UI classes under
// `-default-isolation MainActor`, which is why a build that had been loading
// for weeks stopped loading with no change on this side.
//
// The thunk asks "is the OS new enough to have swift_task_deinitOnExecutor?"
// and calls it if so. That function IS present here (libswift_Concurrency.dylib
// exports it), so the only thing missing is the question, not the answer.
//
// FORWARDS TO the 3-argument _stdlib_isOSVersionAtLeast, which this very dylib
// already exports. That is exactly what Apple's implementation does off
// macCatalyst: the "variant" triple describes the iOS-on-macOS variant of a
// zippered binary, and nothing here is zippered. Discarding it is the correct
// answer for this target, not a shortcut.
//
// ABI: a top-level Swift func with no self, no error and six Builtin.Word
// parameters returning Builtin.Int1 uses x0-x5 and returns in w0 -- identical
// to the C convention, so a plain C function is a valid definition.

#include <stdbool.h>

typedef unsigned long swift_word;

// Swift._stdlib_isOSVersionAtLeast(Builtin.Word, Builtin.Word, Builtin.Word) -> Builtin.Int1
extern bool mr_stdlib_isOSVersionAtLeast(swift_word major,
                                         swift_word minor,
                                         swift_word patch)
    __asm__("_$ss26_stdlib_isOSVersionAtLeastyBi1_Bw_BwBwtF");

// Swift._stdlib_isOSVersionAtLeastOrVariantVersion(...) -> Builtin.Int1
bool mr_stdlib_isOSVersionAtLeastOrVariantVersion(swift_word major,
                                                  swift_word minor,
                                                  swift_word patch,
                                                  swift_word variantMajor,
                                                  swift_word variantMinor,
                                                  swift_word variantPatch)
    __asm__("_$ss042_stdlib_isOSVersionAtLeastOrVariantVersiondE0yBi1_Bw_BwBwBwBwBwtF");

bool mr_stdlib_isOSVersionAtLeastOrVariantVersion(swift_word major,
                                                  swift_word minor,
                                                  swift_word patch,
                                                  swift_word variantMajor,
                                                  swift_word variantMinor,
                                                  swift_word variantPatch) {
    (void)variantMajor;
    (void)variantMinor;
    (void)variantPatch;
    return mr_stdlib_isOSVersionAtLeast(major, minor, patch);
}

// ---- heap-object extra inhabitants on the x86_64 iOS-simulator triple -------
// THE MISMATCH. The guest's x86_64 Swift runtime is built for macOS. On
// x86_64 macOS, Objective-C reserves the LOW pointer bit for tagged pointers,
// so the runtime encodes a heap-object pointer's extra inhabitant i as the
// value i << 1 (stdlib/public/SwiftShims/swift/shims/HeapObject.h:
// ObjCReservedLowBits = 1). On the x86_64 iOS SIMULATOR the reserved bit is
// the HIGH bit, and swiftc (lib/IRGen/SwiftTargetInfo.cpp, configureX86_64
// with isSimulatorEnvironment) encodes extra inhabitant i as the value i.
// MEASURED with swiftc 6.4.2 `-emit-ir -O` for `enum E { case a(C), b, c }`:
// `.c` (extra inhabitant 1) is `ret i64 1` for x86_64-apple-ios26.0-simulator
// and `ret i64 2` for x86_64-apple-macos15.0; the same holds for AnyObject,
// `C.Type` and `AnyClass` payloads (function and raw pointers agree).
//
// Index 0 (a plain Optional's nil) is 0 either way, so only a second level
// differs: `C??`, an enum with two or more empty cases over a class, `Any??`.
// When such a value goes through the RUNTIME's value witnesses (unspecialised
// generic code: Dictionary<K, URL?>.subscript, IndexingIterator over
// [UIViewController?], @State storage), the runtime writes `.none` as 0x2 and
// the app's simulator code reads 0x2 as a non-nil reference and retains it.
// MEASURED: stupid social's story viewer faulted in swift_retain(0x2) reading
// `previewURLs[trackId]` (a `[String: URL?]`; URL is one class reference and
// shares Builtin.UnknownObject's value witnesses), and the first navigation
// push faulted in objc_retain(0x2) iterating `[UIViewController?]`.
//
// THE FIX makes the runtime's value witnesses speak the simulator encoding,
// which every iOS-triple image (app, OpenUIKit, SwiftUI, Foundation) was
// compiled with. Before any Swift code runs, the getEnumTagSinglePayload /
// storeEnumTagSinglePayload witnesses of every runtime value witness table
// whose extra inhabitants are a heap-object pointer are replaced by ones that
// call the runtime's own swift_{get,store}EnumTagSinglePayloadGeneric with the
// simulator's extra-inhabitant callbacks (same count: INT_MAX either way):
//   Builtin.NativeObject, UnknownObject (AnyObject, ObjC-compatible classes,
//   one-reference structs such as URL), BridgeObject, thick metatypes,
//   class-bound existentials with 1 or 2 witness tables, existential
//   metatypes with 1 or 2, and opaque existentials (Any) with 0 or 1 (their
//   metadata slot, 3 words in).
// NOT covered (rarer, reported loudly nowhere): existentials with 3+ witness
// tables (runtime-allocated tables), and macOS-compiled Swift code inside the
// runtime dylibs that builds a second-level extra inhabitant concretely.
// Tagged Objective-C pointers would also disagree (low vs high bit); the
// guest's Objective-C runtime is not known to create any.
#if defined(__x86_64__) && defined(__APPLE_EMBEDDED_SIMULATOR__)

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define MR_SWIFTCC __attribute__((swiftcall))
#define MR_LEAST_VALID_POINTER 0x100000000ULL

typedef struct mr_opaque_value mr_opaque_value;
typedef struct mr_metadata mr_metadata;
typedef unsigned MR_SWIFTCC mr_get_xi_tag(const mr_opaque_value *value, unsigned count,
                                          const mr_metadata *payload);
typedef void MR_SWIFTCC mr_store_xi_tag(mr_opaque_value *value, unsigned whichCase, unsigned count,
                                        const mr_metadata *payload);

extern unsigned swift_getEnumTagSinglePayloadGeneric(const mr_opaque_value *value, unsigned emptyCases,
                                                     const mr_metadata *payload,
                                                     mr_get_xi_tag *getTag) MR_SWIFTCC;
extern void swift_storeEnumTagSinglePayloadGeneric(mr_opaque_value *value, unsigned whichCase,
                                                   unsigned emptyCases, const mr_metadata *payload,
                                                   mr_store_xi_tag *storeTag) MR_SWIFTCC;
extern const mr_metadata *swift_getExistentialTypeMetadata(_Bool anyClass, const mr_metadata *superclass,
                                                          size_t count, const void *const *protocols)
    MR_SWIFTCC;
extern const mr_metadata *swift_getExistentialMetatypeMetadata(const mr_metadata *instance) MR_SWIFTCC;
extern const mr_metadata *swift_getMetatypeMetadata(const mr_metadata *instance) MR_SWIFTCC;

extern char mr_vw_Bo[] __asm__("_$sBoWV");
extern char mr_vw_BO[] __asm__("_$sBOWV");
extern char mr_vw_Bb[] __asm__("_$sBbWV");
extern char mr_md_Any[] __asm__("_$sypN"); // full metadata (see below)
extern char mr_md_Int[] __asm__("_$sSiN");
extern char mr_pd_CustomStringConvertible[] __asm__("_$ss23CustomStringConvertibleMp");
extern char mr_pd_CustomDebugStringConvertible[] __asm__("_$ss28CustomDebugStringConvertibleMp");

// The simulator's swift_getHeapObjectExtraInhabitantIndex / store (no
// reserved low bits), for a pointer `offset` bytes into the value.
#define MR_SIM_XI(offset)                                                                         \
    static unsigned MR_SWIFTCC mr_get_xi_##offset(const mr_opaque_value *value, unsigned count,  \
                                                  const mr_metadata *payload) {                   \
        (void)count; (void)payload;                                                               \
        uintptr_t bits = *(const uintptr_t *)((const char *)value + offset);                      \
        if (bits >= MR_LEAST_VALID_POINTER) return 0;                                             \
        return (unsigned)((int)bits + 1);                                                         \
    }                                                                                             \
    static void MR_SWIFTCC mr_store_xi_##offset(mr_opaque_value *value, unsigned whichCase,      \
                                                unsigned count, const mr_metadata *payload) {     \
        (void)count; (void)payload;                                                               \
        *(uintptr_t *)((char *)value + offset) = (uintptr_t)(whichCase - 1);                      \
    }                                                                                             \
    static unsigned MR_SWIFTCC mr_vw_get_##offset(const mr_opaque_value *value, unsigned empty,  \
                                                  const mr_metadata *self) {                      \
        return swift_getEnumTagSinglePayloadGeneric(value, empty, self, mr_get_xi_##offset);      \
    }                                                                                             \
    static void MR_SWIFTCC mr_vw_store_##offset(mr_opaque_value *value, unsigned whichCase,      \
                                                unsigned empty, const mr_metadata *self) {        \
        swift_storeEnumTagSinglePayloadGeneric(value, whichCase, empty, self, mr_store_xi_##offset); \
    }

MR_SIM_XI(0)
MR_SIM_XI(24)

// ValueWitnessTable (x86_64): six copy/destroy witnesses, then
// getEnumTagSinglePayload at word 6 and storeEnumTagSinglePayload at word 7.
static void mr_use_simulator_xi(void *table, int metadataSlot) {
    void **witnesses = (void **)table;
    witnesses[6] = metadataSlot ? (void *)mr_vw_get_24 : (void *)mr_vw_get_0;
    witnesses[7] = metadataSlot ? (void *)mr_vw_store_24 : (void *)mr_vw_store_0;
}

static void *mr_value_witnesses(const mr_metadata *metadata) {
    return ((void *const *)metadata)[-1];
}

__attribute__((constructor)) static void mr_simulator_heap_object_extra_inhabitants(void) {
    static int done;
    if (done) return;
    done = 1;
    // Diagnostics only: keep the runtime's macOS encoding to reproduce the
    // mismatch (full/iostarget/heap_xi_guest.sh --unpatched).
    if (getenv("OPENUIKIT_KEEP_MACOS_HEAP_EXTRA_INHABITANTS")) return;
    const void *one[1] = {mr_pd_CustomStringConvertible};
    const void *two[2] = {mr_pd_CustomStringConvertible, mr_pd_CustomDebugStringConvertible};
    if (mr_pd_CustomDebugStringConvertible < mr_pd_CustomStringConvertible) {
        two[0] = mr_pd_CustomDebugStringConvertible;
        two[1] = mr_pd_CustomStringConvertible;
    }

    mr_use_simulator_xi(mr_vw_Bo, 0);
    mr_use_simulator_xi(mr_vw_BO, 0);
    mr_use_simulator_xi(mr_vw_Bb, 0);
    mr_use_simulator_xi(mr_value_witnesses(swift_getMetatypeMetadata((const mr_metadata *)mr_md_Int)), 0);
    for (size_t n = 1; n <= 2; n++) {
        const void *const *protocols = n == 1 ? one : two;
        // ProtocolClassConstraint: Class is false, Any is true.
        const mr_metadata *classBound = swift_getExistentialTypeMetadata(0, NULL, n, protocols);
        mr_use_simulator_xi(mr_value_witnesses(classBound), 0);
        mr_use_simulator_xi(mr_value_witnesses(swift_getExistentialMetatypeMetadata(classBound)), 0);
    }
    // `$sypN` is defined by the runtime's C++ (KnownMetadata.cpp) as FULL
    // metadata: the symbol is the value witness table pointer itself, one
    // word before the address point (MEASURED: reading word -1 faulted).
    mr_use_simulator_xi(*(void *const *)mr_md_Any, 1);
    mr_use_simulator_xi(mr_value_witnesses(swift_getExistentialTypeMetadata(1, NULL, 1, one)), 1);
}

#endif
