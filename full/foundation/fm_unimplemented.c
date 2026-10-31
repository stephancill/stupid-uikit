/* fm_unimplemented.c -- the remaining symbols standing between the ported
 * FoundationEssentials and a Mach-O that machorun can load.
 *
 * MEASUREMENT SCAFFOLD, NOT A FIX.  Every symbol here is genuinely absent from
 * machorun's libSystem: computed as the set difference between the link's
 * undefined symbols and the 674 names libSystem.B.tbd exports, with a control
 * (_memcpy/_strlen/_pthread_create/_sysctl must all be present, and an earlier
 * over-specific grep failed that control before this parser replaced it).
 * Belongs beside the FileManager gap list; it does not close it.
 *
 * THE RULE THIS FILE FOLLOWS.  A stub that returns is indistinguishable from
 * an implementation that works, so nothing here returns a made-up answer.
 * Three categories only:
 *
 *   IMPLEMENTED   the answer is defined and machine-independent, so it is
 *                 simply computed: abs, labs, strncasecmp_l in the C locale.
 *   DELEGATED     the caller ALREADY has a designed fallback for failure, so
 *                 the honest answer is to report failure and let upstream take
 *                 the path it wrote for exactly this: vm_copy.
 *   LOUD          everything else -- name itself on fd 2 and abort().  Not a
 *                 no-op, not a zero: if the oracle ever reaches one, the run
 *                 dies saying which.
 *
 * write(2) rather than printf, and the message is built by hand, because a
 * stub that aborts must not depend on stdio being in a usable state.
 */

typedef long ssize_t_;
extern ssize_t_ write(int, const void *, unsigned long);
extern void abort(void);
extern void *memmove(void *, const void *, unsigned long);

static void mr_die(const char *name)
{
    static const char a[] = "fm_unimplemented: ";
    static const char b[] = " is not implemented on this stack "
                            "(machorun libSystem exports no such symbol).\n";
    unsigned long n = 0;
    while (name[n]) n++;
    write(2, a, sizeof(a) - 1);
    write(2, name, n);
    write(2, b, sizeof(b) - 1);
    abort();
}

/* ---- IMPLEMENTED -------------------------------------------------------- */

int abs(int v)        { return v < 0 ? -v : v; }
long labs(long v)     { return v < 0 ? -v : v; }

/* strncasecmp_l with the C locale.  swift-foundation's own string_shims.c
 * calls it precisely to get locale-INDEPENDENT comparison, so the C-locale
 * answer is the only one it ever wants; a non-NULL locale would mean the
 * caller wanted something else and is refused rather than approximated. */
static int mr_lower(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') ? c - 'A' + 'a' : c;
}
int strncasecmp_l(const char *a, const char *b, unsigned long n, void *loc)
{
    if (loc) mr_die("strncasecmp_l with a non-C locale");
    for (unsigned long i = 0; i < n; i++) {
        int x = mr_lower((unsigned char)a[i]);
        int y = mr_lower((unsigned char)b[i]);
        if (x != y) return x - y;
        if (x == 0) return 0;
    }
    return 0;
}

/* mktemp(3): replace the template's trailing X's so that it names a path that
 * does not exist when checked.  swift-foundation's atomic Data write
 * (createTemporaryFile) is the caller: it opens the name with O_CREAT|O_EXCL
 * and asks for a new one on EEXIST, so mktemp's own race is handled upstream,
 * exactly as with libSystem's.  The letters come from a per-process counter
 * mixed with the pid and the template address (no randomness source is
 * assumed); mktemp promises uniqueness at check time, not unpredictability.
 * stupid social writes its caches with `.atomic` at launch. */
extern int access(const char *, int);
extern int getpid(void);
extern int *__error(void);

char *mktemp(char *template_)
{
    static const char alphabet[] =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    static unsigned long long counter;
    unsigned long n = 0, xs = 0;
    while (template_[n]) n++;
    while (xs < n && template_[n - 1 - xs] == 'X') xs++;
    if (xs == 0) { *__error() = 22; /* EINVAL */ return template_; }
    for (int attempt = 0; attempt < 1 << 16; attempt++) {
        unsigned long long v = (++counter) * 0x9E3779B97F4A7C15ull
            ^ ((unsigned long long)getpid() << 32)
            ^ (unsigned long long)(unsigned long)template_;
        for (unsigned long i = 0; i < xs; i++) {
            template_[n - xs + i] = alphabet[v % 62];
            v = v / 62 ^ (v * 0x2545F4914F6CDD1Dull);
        }
        if (access(template_, 0 /* F_OK */) != 0) return template_;
    }
    *__error() = 17; /* EEXIST */
    template_[0] = 0;
    return template_;
}

/* ---- DELEGATED ---------------------------------------------------------- */

/* Platform.copyMemoryPages (Platform.swift:63) reads:
 *     if vm_copy(...) != KERN_SUCCESS { memmove(dest, source, length) }
 * so reporting failure hands control to a fallback UPSTREAM WROTE for this
 * exact case.  KERN_FAILURE is 5.  Inventing a virtual-copy success would be
 * the made-up answer; this is not. */
int vm_copy(unsigned int task, unsigned long src, unsigned long size, unsigned long dst)
{
    (void)task; (void)src; (void)size; (void)dst;
    return 5;
}

/* ---- LOUD --------------------------------------------------------------- */

#define MR_STUB(name) void name(void) { mr_die(#name); }

MR_STUB(chflags)
MR_STUB(confstr)
MR_STUB(fchmod)
MR_STUB(getattrlist)
MR_STUB(link)
MR_STUB(sysctlbyname)
MR_STUB(utimes)
#ifndef OPEN_FOUNDATION_UUID_COMPAT
MR_STUB(uuid_generate_random)
MR_STUB(uuid_parse)
MR_STUB(uuid_unparse_upper)
#endif
