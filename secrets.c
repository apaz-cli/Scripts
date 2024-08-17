#if 0
#This is a shebang.
TMP="$(mktemp -d)"; cc -o "$TMP/a.out" -x c "$0" && "$TMP/a.out" $@; RVAL=$?; rm -rf "$TMP"; exit $RVAL
#endif

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>

#define SMALL_FILE_THRESHOLD 1024 // 1 KB
#define DUMMY_BITS 20

typedef struct {
  char *filename;
  time_t last_access;
  mode_t permissions;
  size_t size;
} FileMetadata;

#include <stdint.h>

#define ROTL(d, lrot) ((d << (lrot)) | (d >> (8 * sizeof(d) - (lrot))))

typedef struct {
  uint64_t wState, xState, yState, zState;
} RomuQuad;

static inline uint64_t romuQuad_random(RomuQuad *rq) {
  uint64_t wp = rq->wState, xp = rq->xState, yp = rq->yState, zp = rq->zState;
  rq->wState = 15241094284759029579u * zp; // a-mult
  rq->xState = zp + ROTL(wp, 52);          // b-rotl, c-add
  rq->yState = yp - xp;                    // d-sub
  rq->zState = yp + wp;                    // e-add
  rq->zState = ROTL(rq->zState, 19);       // f-rotl
  return xp;
}

static inline void encrypt(char *data, size_t size, const char *password) {
  RomuQuad state = {0, 0, 0, 0};
  size_t password_len = strlen(password);

  // Init PRNG state using password
  for (size_t i = 0; i < password_len; i++) {
    state.wState ^= (uint64_t)password[i] << (8 * ((i + 0) % 8));
    state.xState ^= (uint64_t)password[i] << (8 * ((i + 1) % 8));
    state.yState ^= (uint64_t)password[i] << (8 * ((i + 2) % 8));
    state.zState ^= (uint64_t)password[i] << (8 * ((i + 3) % 8));
  }

  // XOR each byte of data with a pseudo-random byte
  for (size_t i = 0; i < size; i++)
    data[i] ^= (char)(romuQuad_random(&state) & 0xFF);
}

static inline void decrypt(char *data, size_t size, const char *password) {
  encrypt(data, size, password);
}

static inline void write_metadata(FILE *archive, const FileMetadata *metadata,
                                  const char *password) {
  size_t filename_len = strlen(metadata->filename);
  size_t total_size = sizeof(size_t) + filename_len + sizeof(time_t) +
                      sizeof(mode_t) + sizeof(size_t);
  char *buffer = malloc(total_size);
  if (!buffer) {
    perror("Error allocating memory for metadata buffer");
    exit(1);
  }

  char *ptr = buffer;
  memcpy(ptr, &filename_len, sizeof(size_t));
  ptr += sizeof(size_t);
  memcpy(ptr, metadata->filename, filename_len);
  ptr += filename_len;
  memcpy(ptr, &metadata->last_access, sizeof(time_t));
  ptr += sizeof(time_t);
  memcpy(ptr, &metadata->permissions, sizeof(mode_t));
  ptr += sizeof(mode_t);
  memcpy(ptr, &metadata->size, sizeof(size_t));

  encrypt(buffer, total_size, password);
  fwrite(&total_size, sizeof(size_t), 1, archive);
  fwrite(buffer, 1, total_size, archive);

  free(buffer);
}

// Read metadata from file
static inline void read_metadata(FILE *archive, FileMetadata *metadata,
                                 const char *password) {
  size_t total_size;
  fread(&total_size, sizeof(size_t), 1, archive);

  char *buffer = malloc(total_size);
  if (!buffer) {
    perror("Error allocating memory for metadata buffer");
    exit(1);
  }

  fread(buffer, 1, total_size, archive);
  decrypt(buffer, total_size, password);

  char *ptr = buffer;
  size_t filename_len;
  memcpy(&filename_len, ptr, sizeof(size_t));
  ptr += sizeof(size_t);

  metadata->filename = malloc(filename_len + 1);
  if (!metadata->filename) {
    perror("Error allocating memory for filename");
    free(buffer);
    exit(1);
  }
  memcpy(metadata->filename, ptr, filename_len);
  metadata->filename[filename_len] = '\0';
  ptr += filename_len;

  memcpy(&metadata->last_access, ptr, sizeof(time_t));
  ptr += sizeof(time_t);
  memcpy(&metadata->permissions, ptr, sizeof(mode_t));
  ptr += sizeof(mode_t);
  memcpy(&metadata->size, ptr, sizeof(size_t));

  free(buffer);
}

// Add a file to the archive
static inline void add_file(FILE *archive, const char *filename,
                            const char *password) {
  FILE *input = fopen(filename, "rb");
  if (!input) {
    perror("Error opening input file");
    return;
  }

  struct stat st;
  if (stat(filename, &st) != 0) {
    perror("Error getting file stats");
    fclose(input);
    return;
  }

  FileMetadata metadata;
  metadata.filename = strdup(filename);
  if (!metadata.filename) {
    perror("Error allocating memory for filename");
    fclose(input);
    return;
  }
  metadata.last_access = st.st_atime;
  metadata.permissions = st.st_mode;
  metadata.size = st.st_size;

  write_metadata(archive, &metadata, password);

  char *buffer = malloc(st.st_size);
  if (!buffer) {
    perror("Error allocating memory for file buffer");
    free(metadata.filename);
    fclose(input);
    return;
  }

  size_t bytes_read = fread(buffer, 1, st.st_size, input);
  if (bytes_read != st.st_size) {
    perror("Error reading file");
    free(buffer);
    free(metadata.filename);
    fclose(input);
    return;
  }

  encrypt(buffer, bytes_read, password);
  fwrite(buffer, 1, bytes_read, archive);

  // Debug print
  printf("Added file: %s\n", filename);

  free(buffer);
  free(metadata.filename);
  fclose(input);
}

// Extract a file from the archive
// Write dummy value for password verification
static inline void write_dummy(FILE *archive, const char *password) {
  char dummy[DUMMY_BITS] = {0}; // Initialize with zeros
  encrypt(dummy, DUMMY_BITS, password);
  fwrite(dummy, 1, DUMMY_BITS, archive);
}

// Read and verify dummy value
static inline int read_dummy(FILE *archive, const char *password) {
  char dummy[DUMMY_BITS];
  if (fread(dummy, 1, DUMMY_BITS, archive) != DUMMY_BITS) {
    perror("Error reading dummy value");
    return 0;
  }
  decrypt(dummy, DUMMY_BITS, password);
  for (int i = 0; i < DUMMY_BITS; i++) {
    if (dummy[i] != 0) {
      return 0; // Decryption failed
    }
  }
  return 1; // Decryption succeeded
}

static inline void extract_file(FILE *archive, const char *output_dir,
                                const char *password) {
  FileMetadata metadata;
  read_metadata(archive, &metadata, password);

  char *output_path =
      malloc(strlen(output_dir) + strlen(metadata.filename) + 2);
  if (!output_path) {
    perror("Error allocating memory for output path");
    free(metadata.filename);
    return;
  }
  sprintf(output_path, "%s/%s", output_dir, metadata.filename);

  // Create directories if they don't exist
  char *dir_path = strdup(output_path);
  char *p = strrchr(dir_path, '/');
  if (p) {
    *p = '\0';
    for (char *q = dir_path + 1; *q; q++) {
      if (*q == '/') {
        *q = '\0';
        mkdir(dir_path, 0755);
        *q = '/';
      }
    }
    mkdir(dir_path, 0755);
  }
  free(dir_path);

  FILE *output = fopen(output_path, "wb");
  if (!output) {
    perror("Error opening output file");
    free(output_path);
    free(metadata.filename);
    return;
  }

  char *buffer = malloc(metadata.size);
  if (!buffer) {
    perror("Error allocating memory for file buffer");
    fclose(output);
    free(output_path);
    free(metadata.filename);
    return;
  }

  size_t bytes_read = fread(buffer, 1, metadata.size, archive);
  if (bytes_read != metadata.size) {
    perror("Error reading from archive");
    free(buffer);
    fclose(output);
    free(output_path);
    free(metadata.filename);
    return;
  }

  decrypt(buffer, bytes_read, password);
  fwrite(buffer, 1, bytes_read, output);

  fclose(output);

  // Debug print
  printf("Extracted file: %s\n", output_path);

  // Restore metadata
  struct utimbuf times;
  times.actime = metadata.last_access;
  times.modtime = time(NULL);
  utime(output_path, &times);
  chmod(output_path, metadata.permissions);

  free(buffer);
  free(output_path);
  free(metadata.filename);
}

// Create an archive
static inline void create_archive(const char *archive_name,
                                  const char *password,
                                  int num_inputs,
                                  char **input_files) {
  FILE *archive = fopen(archive_name, "wb");
  if (!archive) {
    perror("Error creating archive");
    return;
  }

  // Write dummy value for password verification
  write_dummy(archive, password);

  for (int i = 0; i < num_inputs; i++) {
    add_file(archive, input_files[i], password);
  }

  fclose(archive);
}

// Extract files from an archive
static inline void extract_archive(const char *archive_name,
                                   const char *output_dir,
                                   const char *password) {
  FILE *archive = fopen(archive_name, "rb");
  if (!archive) {
    perror("Error opening archive");
    exit(1);
  }

  // Verify password using dummy value
  if (!read_dummy(archive, password)) {
    fprintf(stderr, "Error: Incorrect password or corrupted archive.\n");
    exit(1);
  }

  mkdir(output_dir, 0755);

  while (!feof(archive)) {
    long pos = ftell(archive);
    FileMetadata metadata;
    if (fread(&metadata, sizeof(FileMetadata), 1, archive) != 1) {
      break;
    }
    fseek(archive, pos, SEEK_SET);
    extract_file(archive, output_dir, password);
  }

  fclose(archive);
}

static inline void print_usage(void) {
  fprintf(stderr, "Usage: secrets <create|extract> <archive_name> <password> [input_files_and_folders]...\n");
  fprintf(stderr, "       secrets extract <archive_name> <password> [output_directory]\n");
}

static inline void print_help(void) {
  fprintf(stderr, "Usage: secrets [OPTIONS] <create|extract> <archive_name> <password> [input_files_and_folders]...\n");
  fprintf(stderr, "       secrets [OPTIONS] extract <archive_name> <password> [output_directory]\n");
  fprintf(stderr, "\nOptions:\n");
  fprintf(stderr, "  --help     Display this help message and exit\n");
  fprintf(stderr, "\nModes:\n");
  fprintf(stderr, "  create     Create a new archive\n");
  fprintf(stderr, "  extract    Extract files from an existing archive\n");
  fprintf(stderr, "\nArguments:\n");
  fprintf(stderr, "  output_directory    Optional. Directory to extract files to (default: current directory)\n");
}

int main(int argc, char **argv) {
  if (argc < 4)
    return print_usage(), 1;

  for (int i = 1; i < argc; i++)
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)
      return print_help(), 0;

  const char *mode = argv[1];
  const char *archive_name = argv[2];
  const char *password = argv[3];

  if (strcmp(mode, "create") == 0) {
    if (argc < 5) {
      fprintf(stderr, "Error: No input files specified for create mode.\n");
      return print_usage(), 1;
    }
    create_archive(archive_name, password, argc - 4, &argv[4]);
  } else if (strcmp(mode, "extract") == 0) {
    if (argc < 4 || argc > 5) {
      fprintf(stderr, "Error: Incorrect number of arguments for extract mode.\n");
      return print_usage(), 1;
    }
    const char *output_dir = (argc == 5) ? argv[4] : ".";
    extract_archive(archive_name, output_dir, password);
  } else {
    fprintf(stderr, "Invalid mode. Use 'create' or 'extract'.\n");
    return 1;
  }

  return 0;
}
