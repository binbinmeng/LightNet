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

#ifndef _LN_PARAM_H_
#define _LN_PARAM_H_

#include "ln_list.h"

typedef enum ln_param_type ln_param_type;
enum ln_param_type {
     /* NULL should always be the first type */
     LN_PARAM_NULL = 0,
     LN_PARAM_STRING,
     LN_PARAM_NUMBER,
     LN_PARAM_BOOL,
     LN_PARAM_ARRAY_STRING,
     LN_PARAM_ARRAY_NUMBER,
     LN_PARAM_ARRAY_BOOL,
     LN_PARAM_INVALID
     /* INVALID should always be the last type */
};

typedef struct ln_param_entry ln_param_entry;
struct ln_param_entry {
     char          *arg_name;
     ln_param_type  type;
     int            array_len;
     double         value_double;
     int            value_int;
     ln_bool        value_bool;
     char          *value_string;
     char         **value_array_string;
     double        *value_array_double;
     int           *value_array_int;
     ln_bool       *value_array_bool;
};

typedef ln_list ln_param_table;

#ifdef __cplusplus
LN_CPPSTART
#endif

ln_param_table *ln_param_table_create(void);
ln_param_table *ln_param_table_append_string(ln_param_table *table,
                                             const char *arg_name,
                                             const char *string);
ln_param_table *ln_param_table_append_number(ln_param_table *table,
                                             const char *arg_name,
                                             double number);
ln_param_table *ln_param_table_append_bool(ln_param_table *table,
                                           const char *arg_name,
                                           ln_bool bool);
ln_param_table *ln_param_table_append_null(ln_param_table *table,
                                           const char *arg_name);
ln_param_table *ln_param_table_append_array_string(ln_param_table *table,
                                                   const char *arg_name,
                                                   int array_len,
                                                   char **array_string);
ln_param_table *ln_param_table_append_array_number(ln_param_table *table,
                                                   const char *arg_name,
                                                   int array_len,
                                                   double *array_number);
ln_param_table *ln_param_table_append_array_bool(ln_param_table *table,
                                                 const char *arg_name,
                                                 int array_len,
                                                 ln_bool *array_bool);
void ln_param_table_free(ln_param_table *table);
ln_param_entry *ln_param_table_find_by_arg_name(ln_param_table *table,
						char *arg_name);
int ln_param_table_length(ln_param_table *table);
const char *ln_param_type_name(ln_param_type type);

#ifdef __cplusplus
LN_CPPEND
#endif

#endif	/* _LN_PARAM_H_ */
