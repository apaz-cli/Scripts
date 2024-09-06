#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>

void *infinite_loop(void *unused) {
  while (1)
    ;
}

char *store_mem = NULL;

void alloc_mem(int n_gb) {
  if (n_gb <= 0)
    return;

  size_t n_b = (size_t)n_gb * 1000 * 1000 * 1000;
  store_mem = (char *)calloc(1, n_b);
  if (!store_mem)
    puts("malloc() failed."), exit(1);

  for (size_t i = 0; i < n_b; i++)
    store_mem[i] = 0;
}

void load_threads(void) {
  int numThreads =
      sysconf(_SC_NPROCESSORS_ONLN) - 1; // Get the number of processors.
  pthread_t threads[numThreads];
  int rc;
  for (size_t t = 0; t < numThreads; t++) {
    rc = pthread_create(&threads[t], NULL, infinite_loop, NULL);
    if (rc) {
      printf("ERROR; return code from pthread_create() is %d\n", rc);
      exit(1);
    }
  }

  infinite_loop(NULL);
}

int main(int argc, char **argv) {

  int n_gb = -1;
  if (argc < 2)
    n_gb = 0;
  else if (argc == 2)
    n_gb = atoi(argv[1]);
  else
    return puts("Usage: load_all_threads <n_gb>"), 1;

  alloc_mem(n_gb);
  load_threads();
  return 0;
}
