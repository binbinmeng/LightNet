/*
 * Copyright (c) 2018 Zhao Zhixu
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _LN_MSG_H_
#define _LN_MSG_H_

#include "ln_hash.h"

enum ln_msg_level {
    LN_ERROR,
    LN_ERROR_SYS,
    LN_INTER_ERROR,
    LN_INTER_ERROR_SYS,
    LN_WARNING,
    LN_WARNING_SYS,
    LN_INTER_WARNING,
    LN_INTER_WARNING_SYS,
    LN_DEBUG_INFO,
    LN_INFO
};
typedef enum ln_msg_level ln_msg_level;

struct ln_msg {
    char            *err_str;
    ln_msg_level   level;
};
typedef struct ln_msg ln_msg;

#define ln_msg_emit(level, fmt, varg...)                        \
    do {                                                        \
        ln_msg *err = ln_msg_create((level), (fmt), ##varg);    \
        ln_msg_handle(&err);                                    \
    } while (0)

#define ln_msg_emit_once(hash, key, level, fmt, varg...)        \
    do {                                                        \
        if (!ln_hash_find((hash), (key))) {                     \
            ln_hash_insert((hash), (key), (void *)1);           \
            ln_msg_emit((level), (fmt), ##varg);                \
        }                                                       \
    } while (0)

#define ln_msg_error(fmt, varg...)              \
    ln_msg_emit(LN_ERROR, (fmt), ##varg)

#define ln_msg_error_sys(fmt, varg...)          \
    ln_msg_emit(LN_ERROR_SYS, (fmt), ##varg)

#define ln_msg_inter_error(fmt, varg...)        \
    ln_msg_emit(LN_INTER_ERROR, (fmt), ##varg)

#define ln_msg_inter_error_sys(fmt, varg...)            \
    ln_msg_emit(LN_INTER_ERROR_SYS, (fmt), ##varg)

#define ln_msg_warning(fmt, varg...)            \
    ln_msg_emit(LN_WARNING, (fmt), ##varg)

#define ln_msg_warning_sys(fmt, varg...)        \
    ln_msg_emit(LN_WARNING_SYS, (fmt), ##varg)

#define ln_msg_inter_warning(fmt, varg...)              \
    ln_msg_emit(LN_INTER_WARNING, (fmt), ##varg)

#define ln_msg_inter_warning_sys(fmt, varg...)          \
    ln_msg_emit(LN_INTER_WARNING_SYS, (fmt), ##varg)

#ifdef LN_DEBUG
#define ln_msg_debug(fmt, varg...)              \
    ln_msg_emit(LN_DEBUG_INFO, (fmt), ##varg)
#else
#define ln_msg_debug(fmt, varg...) (void)0
#endif

#define ln_msg_info(fmt, varg...)               \
    ln_msg_emit(LN_INFO, (fmt), ##varg)

#ifdef __cplusplus
LN_CPPSTART
#endif

ln_msg *ln_msg_create(ln_msg_level level, const char *fmt, ...);
void ln_msg_free(ln_msg *error);
void ln_msg_handle(ln_msg **error);

#ifdef __cplusplus
LN_CPPEND
#endif

#endif	/* _LN_MSG_H_ */
