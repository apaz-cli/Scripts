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

typedef struct {
  char *filename;
  time_t last_access;
  mode_t permissions;
  size_t size;
} FileMetadata;

#include <stdint.h>

// 64-bit xorshift pseudo-random number generator
uint64_t xorshift64(uint64_t *state) {
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

void encrypt(char *data, size_t size, const char *password) {
    uint64_t state = 0;
    size_t password_len = strlen(password);
    
    // Initialize the PRNG state using the password
    for (size_t i = 0; i < password_len; i++) {
        state = state * 31 + password[i];
    }
    
    // XOR each byte of data with a pseudo-random byte
    for (size_t i = 0; i < size; i++) {
        data[i] ^= (char)(xorshift64(&state) & 0xFF);
    }
}

void decrypt(char *data, size_t size, const char *password) {
    // Decryption is the same as encryption for this method
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
void extract_file(FILE *archive, const char *output_dir, const char *password) {
  FileMetadata metadata;
  read_metadata(archive, &metadata);

  char *output_path = malloc(strlen(output_dir) + strlen(metadata.filename) + 2);
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
