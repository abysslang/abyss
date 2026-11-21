#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

static atomic_int mode;
static atomic_int balance;

void thread_test_inject(int next) { atomic_store(&mode, next); }
int thread_test_balance(void) { return atomic_load(&balance); }

uint64_t thread_test_monotonic_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) abort();
    return (uint64_t)now.tv_sec * 1000000000 + (uint64_t)now.tv_nsec;
}

static int fails(int expected) { return atomic_compare_exchange_strong(&mode, &expected, 0); }

void *__real_malloc(size_t size);
void __real_free(void *ptr);
int __real_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
int __real_pthread_join(pthread_t, void **);
int __real_pthread_mutex_init(pthread_mutex_t *, const pthread_mutexattr_t *);
int __real_nanosleep(const struct timespec *, struct timespec *);

void *__wrap_malloc(size_t size) {
    if (fails(1)) return NULL;
    void *ptr = __real_malloc(size);
    if (ptr) atomic_fetch_add(&balance, 1);
    return ptr;
}

void __wrap_free(void *ptr) {
    __real_free(ptr);
    if (ptr) atomic_fetch_sub(&balance, 1);
}

int __wrap_pthread_create(pthread_t *out, const pthread_attr_t *attr, void *(*run)(void *), void *arg) {
    return fails(2) ? 101 : __real_pthread_create(out, attr, run, arg);
}

int __wrap_pthread_join(pthread_t thread, void **result) {
    return fails(3) ? 102 : __real_pthread_join(thread, result);
}

int __wrap_pthread_mutex_init(pthread_mutex_t *lock, const pthread_mutexattr_t *attr) {
    return fails(4) ? 103 : __real_pthread_mutex_init(lock, attr);
}

int __wrap_nanosleep(const struct timespec *delay, struct timespec *remaining) {
    if (fails(5)) {
        errno = 104;
        return -1;
    }
    if (fails(6)) {
        if (delay->tv_sec != 1 || delay->tv_nsec != 250000000) abort();
        *remaining = (struct timespec){ 0, 5000000 };
        thread_test_inject(7);
        errno = EINTR;
        return -1;
    }
    if (fails(7)) {
        if (delay->tv_sec != 0 || delay->tv_nsec != 5000000) abort();
        return 0;
    }
    if (fails(8)) {
        if ((uint64_t)delay->tv_sec != UINT64_MAX / 1000 || delay->tv_nsec != 615000000) abort();
        return 0;
    }
    return __real_nanosleep(delay, remaining);
}
