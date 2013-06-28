#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "ignore.h"
#include "log.h"
#include "options.h"
#include "print.h"
#include "util.h"

int first_file_match = 1;

const char *color_reset = "\e[0m\e[K";

void print_path(const char* path, const char sep) {
    log_debug("printing path");
    path = normalize_path(path);

    if (opts.ackmate) {
        fprintf(out_fd, ":%s%c", path, sep);
    } else {
        if (opts.color) {
            fprintf(out_fd, "%s%s%s%c", opts.color_path, path, color_reset, sep);
        } else {
            fprintf(out_fd, "%s%c", path, sep);
        }
    }
}

void print_binary_file_matches(const char* path) {
    path = normalize_path(path);
    print_file_separator();
    fprintf(out_fd, "Binary file %s matches.\n", path);
}
/*
const int MOD_ADLER = 65521;
static uint32_t adler32(const unsigned char *data, size_t len) {
    uint32_t a = 1, b = 0;
    int32_t index;
    
    for (index = 0; index < len; ++index) {
        a = (a + data[index]) % MOD_ADLER;
        b = (b + a) % MOD_ADLER;
    }
    
    return (b << 16) | a;
}
*/

void print_file_matches(const char* path, const char* buf, const int buf_len, const match matches[], const int matches_len) {
    
    NSMutableArray* matchesArray = [NSMutableArray array];
    NSMutableDictionary* matchesDict = [NSMutableDictionary dictionaryWithCapacity:32];
    matchesDict[@"checksum"] = @(adler32(adler32(0L, Z_NULL, 0), buf, buf_len));
    matchesDict[@"path"] = @(path);
    matchesDict[@"matches"] = matchesArray;
    
    int line = 1;
    char **context_prev_lines = NULL;
    int prev_line = 0;
    int last_prev_line = 0;
    int prev_line_offset = 0;
    int cur_match = 0;
    /* TODO the line below contains a terrible hack */
    int lines_since_last_match = 1000000; /* if I initialize this to INT_MAX it'll overflow */
    int lines_to_print = 0;
    int last_printed_match = 0;
    char sep = '-';
    int i, j;
    int in_a_match = FALSE;
    int printing_a_match = FALSE;

    if (opts.ackmate) {
        sep = ':';
    }

    print_file_separator();

    if (opts.print_heading == TRUE) {
        print_path(path, '\n');
    }

    context_prev_lines = ag_calloc(sizeof(char*), (opts.before + 1));

    for (i = 0; i <= buf_len && (cur_match < matches_len || lines_since_last_match <= opts.after); i++) {        
        if (cur_match < matches_len && i == matches[cur_match].end) {
            /* We found the end of a match. */
            cur_match++;
            in_a_match = FALSE;
        }

        if (cur_match < matches_len && i == matches[cur_match].start) {
            in_a_match = TRUE;
            /* We found the start of a match */
            if (cur_match > 0 && opts.context && lines_since_last_match > (opts.before + opts.after + 1)) {
                fprintf(out_fd, "--\n");
            }

            if (lines_since_last_match > 0 && opts.before > 0) {
                /* TODO: better, but still needs work */
                /* print the previous line(s) */
                lines_to_print = lines_since_last_match - (opts.after + 1);
                if (lines_to_print < 0) {
                    lines_to_print = 0;
                } else if (lines_to_print > opts.before) {
                    lines_to_print = opts.before;
                }

                for (j = (opts.before - lines_to_print); j < opts.before; j++) {
                    prev_line = (last_prev_line + j) % opts.before;
                    if (context_prev_lines[prev_line] != NULL) {
                        if (opts.print_heading == 0) {
                            print_path(path, ':');
                        }
                        print_line_number(line - (opts.before - j), sep);
                        fprintf(out_fd, "%s\n", context_prev_lines[prev_line]);
                    }
                }
            }
            lines_since_last_match = 0;
        }

        /* We found the end of a line. */
        if (buf[i] == '\n' && opts.before > 0) {
            if (context_prev_lines[last_prev_line] != NULL) {
                free(context_prev_lines[last_prev_line]);
            }
            /* We don't want to strcpy the \n */
            context_prev_lines[last_prev_line] =
                ag_strndup(&buf[prev_line_offset], i - prev_line_offset);
            last_prev_line = (last_prev_line + 1) % opts.before;
        }

        if (buf[i] == '\n' || i == buf_len) {
            if (lines_since_last_match == 0) {
                if (opts.print_heading == 0 && !opts.search_stream) {
                    print_path(path, ':');
                }

//                if (opts.ackmate) {
                    /* print headers for ackmate to parse */
//                    print_line_number(line, ';');
                    for (; last_printed_match < cur_match; last_printed_match++) {
                        int str_start = matches[last_printed_match].start;
                        int str_end = matches[last_printed_match].end;
                        int str_length = str_end - str_start;
                        
                        [matchesArray addObject:@{
                            @"line": @(line),
                            @"index": @(i),
                            @"start": @(str_start),
                            @"end": @(str_end),
                            @"string": (str_length > 0 ? [[NSString alloc] initWithBytes:buf + str_start length:str_length encoding:NSUTF8StringEncoding] : @""),
                        }];

//                        fprintf(out_fd, "%i %i",
//                              (matches[last_printed_match].start - prev_line_offset),
//                              (matches[last_printed_match].end - matches[last_printed_match].start)
//                        );
//                        last_printed_match == cur_match - 1 ? fputc(':', out_fd) : fputc(',', out_fd);
                    }
                    j = prev_line_offset;
                    /* print up to current char */
//                    for (; j <= i; j++) {
//                        fputc(buf[j], out_fd);
//                    }
/*
                } else {
                    print_line_number(line, ':');
                    if (opts.column) {
                        fprintf(out_fd, "%i:", (matches[last_printed_match].start - prev_line_offset) + 1);
                    }

                    if (printing_a_match && opts.color) {
                        fprintf(out_fd, "%s", opts.color_match);
                    }
                    for (j = prev_line_offset; j <= i; j++) {
                        if (j == matches[last_printed_match].end && last_printed_match < matches_len) {
                            if (opts.color) {
                                fprintf(out_fd, "%s", color_reset);
                            }
                            printing_a_match = FALSE;
                            last_printed_match++;
                        }
                        if (j == matches[last_printed_match].start && last_printed_match < matches_len) {
                            if (opts.color) {
                                fprintf(out_fd, "%s", opts.color_match);
                            }
                            printing_a_match = TRUE;
                        }
                        fputc(buf[j], out_fd);
                    }
                    if (printing_a_match && opts.color) {
                        fprintf(out_fd, "%s", color_reset);
                    }
                }
 */
            } else if (lines_since_last_match <= opts.after) {
                /* print context after matching line */
                if (opts.print_heading == 0) {
                    print_path(path, ':');
                }
                print_line_number(line, sep);

                for (j = prev_line_offset; j < i; j++) {
                    fputc(buf[j], out_fd);
                }
                fputc('\n', out_fd);
            }

            prev_line_offset = i + 1; /* skip the newline */
            line++;
            if (!in_a_match) {
                lines_since_last_match++;
            }
        }
    }
    
    for (i = 0; i < opts.before; i++) {
        if (context_prev_lines[i] != NULL) {
            free(context_prev_lines[i]);
        }
    }
    free(context_prev_lines);
}

void print_line_number(const int line, const char sep) {
    if (!opts.print_line_numbers) {
        return;
    }
    log_debug("printing line number");

    if (opts.color) {
        fprintf(out_fd, "%s%i%s%c", opts.color_line_number, line, color_reset, sep);
    } else {
        fprintf(out_fd, "%i%c", line, sep);
    }
}

void print_file_separator() {
    if (first_file_match == 0 && opts.print_break) {
        log_debug("printing file separator");
        fprintf(out_fd, "\n");
    }
    first_file_match = 0;
}

const char* normalize_path(const char* path) {
    if (strlen(path) >= 3 && path[0] == '.' && path[1] == '/') {
        return path + 2;
    } else {
        return path;
    }
}
