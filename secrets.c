#include <fcntl.h>
#include <glob.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>

#define SMALL_FILE_THRESHOLD 1024 // 1 KB
#define DUMMY_SIZE 64 // Size of the dummy value for password verification

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

uint64_t romuQuad_random(RomuQuad *rq) {
  uint64_t wp = rq->wState, xp = rq->xState, yp = rq->yState, zp = rq->zState;
  rq->wState = 15241094284759029579u * zp; // a-mult
  rq->xState = zp + ROTL(wp, 52);          // b-rotl, c-add
  rq->yState = yp - xp;                    // d-sub
  rq->zState = yp + wp;                    // e-add
  rq->zState = ROTL(rq->zState, 19);       // f-rotl
  return xp;
}

void encrypt(char *data, size_t size, const char *password) {
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

void decrypt(char *data, size_t size, const char *password) {
  // XOR is its own inverse
  encrypt(data, size, password);
}

void write_metadata(FILE *archive, const FileMetadata *metadata) {
  size_t filename_len = strlen(metadata->filename);
  fwrite(&filename_len, sizeof(size_t), 1, archive);
  fwrite(metadata->filename, 1, filename_len, archive);
  fwrite(&metadata->last_access, sizeof(time_t), 1, archive);
  fwrite(&metadata->permissions, sizeof(mode_t), 1, archive);
  fwrite(&metadata->size, sizeof(size_t), 1, archive);
}

// Read metadata from file
void read_metadata(FILE *archive, FileMetadata *metadata) {
  size_t filename_len;
  fread(&filename_len, sizeof(size_t), 1, archive);
  metadata->filename = malloc(filename_len + 1);
  if (!metadata->filename) {
    perror("Error allocating memory for filename");
    exit(1);
  }
  fread(metadata->filename, 1, filename_len, archive);
  metadata->filename[filename_len] = '\0';
  fread(&metadata->last_access, sizeof(time_t), 1, archive);
  fread(&metadata->permissions, sizeof(mode_t), 1, archive);
  fread(&metadata->size, sizeof(size_t), 1, archive);
}

// Add a file to the archive
void add_file(FILE *archive, const char *filename, const char *password) {
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

  write_metadata(archive, &metadata);

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

  if (metadata.size <= SMALL_FILE_THRESHOLD) {
    encrypt(buffer, bytes_read, password);
  }
  fwrite(buffer, 1, bytes_read, archive);

  free(buffer);
  free(metadata.filename);
  fclose(input);
}

// Extract a file from the archive
// Write dummy value for password verification
void write_dummy(FILE *archive, const char *password) {
  char dummy[DUMMY_SIZE] = {0}; // Initialize with zeros
  encrypt(dummy, DUMMY_SIZE, password);
  fwrite(dummy, 1, DUMMY_SIZE, archive);
}

// Read and verify dummy value
int read_dummy(FILE *archive, const char *password) {
  char dummy[DUMMY_SIZE];
  if (fread(dummy, 1, DUMMY_SIZE, archive) != DUMMY_SIZE) {
    perror("Error reading dummy value");
    return 0;
  }
  decrypt(dummy, DUMMY_SIZE, password);
  for (int i = 0; i < DUMMY_SIZE; i++) {
    if (dummy[i] != 0) {
      return 0; // Decryption failed
    }
  }
  return 1; // Decryption succeeded
}

void extract_file(FILE *archive, const char *output_dir, const char *password) {
  FileMetadata metadata;
  read_metadata(archive, &metadata);

  char *output_path =
      malloc(strlen(output_dir) + strlen(metadata.filename) + 2);
  if (!output_path) {
    perror("Error allocating memory for output path");
    free(metadata.filename);
    return;
  }
  sprintf(output_path, "%s/%s", output_dir, metadata.filename);

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

  if (metadata.size <= SMALL_FILE_THRESHOLD) {
    decrypt(buffer, bytes_read, password);
  }
  fwrite(buffer, 1, bytes_read, output);

  fclose(output);

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
void create_archive(const char *archive_name, const char *input_pattern,
                    const char *password) {
  FILE *archive = fopen(archive_name, "wb");
  if (!archive) {
    perror("Error creating archive");
    return;
  }

  // Write dummy value for password verification
  write_dummy(archive, password);

  glob_t globbuf;
  int glob_flags = GLOB_TILDE | GLOB_NOSORT;
  if (glob(input_pattern, glob_flags, NULL, &globbuf) != 0) {
    perror("Error in glob");
    fclose(archive);
    return;
  }

  for (size_t i = 0; i < globbuf.gl_pathc; i++) {
    add_file(archive, globbuf.gl_pathv[i], password);
  }

  globfree(&globbuf);
  fclose(archive);
}

// Extract files from an archive
void extract_archive(const char *archive_name, const char *output_dir,
                     const char *password) {
  FILE *archive = fopen(archive_name, "rb");
  if (!archive) {
    perror("Error opening archive");
    return;
  }

  // Verify password using dummy value
  if (!read_dummy(archive, password)) {
    fprintf(stderr, "Error: Incorrect password or corrupted archive\n");
    fclose(archive);
    return;
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

void print_usage(const char *argv_zero) {
  fprintf(stderr,
          "Usage: %s <create|extract> <archive_name> "
          "<input_pattern|output_dir> <password>\n",
          argv_zero);
}

void print_help(const char *program_name) {
  fprintf(stderr,
          "Usage: %s [OPTIONS] <create|extract> <archive_name> "
          "<input_pattern|output_dir> <password>\n",
          program_name);
  fprintf(stderr, "\nOptions:\n");
  fprintf(stderr, "  --help     Display this help message and exit\n");
  fprintf(stderr, "\nModes:\n");
  fprintf(stderr, "  create     Create a new archive\n");
  fprintf(stderr, "  extract    Extract files from an existing archive\n");
}

int main(int argc, char **argv) {
  if (argc < 5)
    return print_usage(argv[0]), 1;

  for (int i = 1; i < argc; i++)
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)
      return print_help(argv[0]), 0;

  const char *mode = argv[1];
  const char *archive_name = argv[2];
  const char *pattern_or_dir = argv[3];
  const char *password = argv[4];

  if (strcmp(mode, "create") == 0) {
    create_archive(archive_name, pattern_or_dir, password);
  } else if (strcmp(mode, "extract") == 0) {
    extract_archive(archive_name, pattern_or_dir, password);
  } else {
    fprintf(stderr, "Invalid mode. Use 'create' or 'extract'.\n");
    return 1;
  }

  return 0;
}
