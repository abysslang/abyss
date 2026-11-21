#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

static atomic_int mode;
static atomic_int balance;

void thread_test_inject(int next) { atomic_store(&mode, next); }
int thread_test_balance(void) { return atomic_load(&balance); }

static int fails(int expected) { return atomic_compare_exchange_strong(&mode, &expected, 0); }

void *__real_malloc(size_t size);
void __real_free(void *ptr);
int __real_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
int __real_pthread_join(pthread_t, void **);
int __real_pthread_mutex_init(pthread_mutex_t *, const pthread_mutexattr_t *);

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
