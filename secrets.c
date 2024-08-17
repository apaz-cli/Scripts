#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <glob.h>

#define MAX_FILENAME 256
#define SMALL_FILE_THRESHOLD 1024 // 1 KB
#define BUFFER_SIZE 4096

typedef struct {
    char filename[MAX_FILENAME];
    time_t last_access;
    mode_t permissions;
    size_t size;
} FileMetadata;

// LCG parameters
#define LCG_A 1664525
#define LCG_C 1013904223
#define LCG_M 0xFFFFFFFF

// Simple LCG-based stream cipher
uint32_t lcg_state;

uint8_t lcg_next() {
    lcg_state = (LCG_A * lcg_state + LCG_C) & LCG_M;
    return (uint8_t)(lcg_state >> 24);
}

void stream_crypt(char *data, size_t size, const char *password) {
    // Inline init_lcg
    lcg_state = 0;
    for (size_t i = 0; i < strlen(password); i++) {
        lcg_state = (lcg_state * 31 + password[i]) & LCG_M;
    }

    for (size_t i = 0; i < size; i++) {
        data[i] ^= lcg_next();
    }
}

// Encryption function
void encrypt(char *data, size_t size, const char *password) {
    stream_crypt(data, size, password);
}

// Decryption function (identical to encryption due to XOR properties)
void decrypt(char *data, size_t size, const char *password) {
    stream_crypt(data, size, password);
}

// Write metadata to file
void write_metadata(FILE *archive, const FileMetadata *metadata) {
    fwrite(metadata, sizeof(FileMetadata), 1, archive);
}

// Read metadata from file
void read_metadata(FILE *archive, FileMetadata *metadata) {
    fread(metadata, sizeof(FileMetadata), 1, archive);
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
    strncpy(metadata.filename, filename, MAX_FILENAME);
    metadata.last_access = st.st_atime;
    metadata.permissions = st.st_mode;
    metadata.size = st.st_size;

    write_metadata(archive, &metadata);

    char buffer[BUFFER_SIZE];
    size_t bytes_read;
    while ((bytes_read = fread(buffer, 1, BUFFER_SIZE, input)) > 0) {
        if (metadata.size <= SMALL_FILE_THRESHOLD) {
            encrypt(buffer, bytes_read, password);
        }
        fwrite(buffer, 1, bytes_read, archive);
    }

    fclose(input);
}

// Extract a file from the archive
void extract_file(FILE *archive, const char *output_dir, const char *password) {
    FileMetadata metadata;
    read_metadata(archive, &metadata);

    char output_path[MAX_FILENAME * 2];
    snprintf(output_path, sizeof(output_path), "%s/%s", output_dir, metadata.filename);

    FILE *output = fopen(output_path, "wb");
    if (!output) {
        perror("Error opening output file");
        return;
    }

    char buffer[BUFFER_SIZE];
    size_t bytes_read;
    size_t remaining = metadata.size;
    while (remaining > 0 && (bytes_read = fread(buffer, 1, BUFFER_SIZE > remaining ? remaining : BUFFER_SIZE, archive)) > 0) {
        if (metadata.size <= SMALL_FILE_THRESHOLD) {
            decrypt(buffer, bytes_read, password);
        }
        fwrite(buffer, 1, bytes_read, output);
        remaining -= bytes_read;
    }

    fclose(output);

    // Restore metadata
    struct utimbuf times;
    times.actime = metadata.last_access;
    times.modtime = time(NULL);
    utime(output_path, &times);
    chmod(output_path, metadata.permissions);
}

// Create an archive
void create_archive(const char *archive_name, const char *input_pattern, const char *password) {
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
void extract_archive(const char *archive_name, const char *output_dir, const char *password) {
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

int main(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: %s <create|extract> <archive_name> <input_pattern|output_dir> <password>\n", argv[0]);
        return 1;
    }

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