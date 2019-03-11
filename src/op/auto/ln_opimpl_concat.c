/*
 * Copyright (c) 2019 Zhao Zhixu
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

#include <assert.h>
#include "ln_op.h"
#include "ln_arch.h"

struct priv_s {
    ln_tensor_entry *src1_entry;
    ln_tensor_entry *src2_entry;
    ln_tensor_entry *dst_entry;
    ln_param_entry  *axis_entry;
};

/* This function should do the parameter checking and tensor shape inference. */
static void concat_pre_run(ln_op_arg *op_arg)
{
    char                 *src1_name;
    ln_tensor_list_entry *src1_list_entry;
    ln_tensor_entry      *src1_entry;
    tl_tensor            *src1;
    char                 *src2_name;
    ln_tensor_list_entry *src2_list_entry;
    ln_tensor_entry      *src2_entry;
    tl_tensor            *src2;
    char                 *dst_name;
    ln_tensor_list_entry *dst_list_entry;
    ln_tensor_entry      *dst_entry;
    tl_tensor            *dst;
    int                   dst_ndim;
    int                  *dst_dims;
    tl_dtype              dst_dtype;
    int                   axis;
    ln_param_entry       *axis_entry;
    int                   tensors_in_n;
    int                   tensors_out_n;
    int                   params_n;
    struct priv_s        *priv;

    /* check tensors and parameters */
    tensors_in_n = ln_tensor_list_length(op_arg->tensors_in);
    ln_opck_tensors_in_len_eq(tensors_in_n, 2);

    src1_list_entry = ln_tensor_list_find_by_arg_name(op_arg->tensors_in, "src1");
    ln_opck_tensor_in_exist(src1_list_entry, "src1");
    src1_name = src1_list_entry->name;
    src1_entry = ln_tensor_table_find(op_arg->tensor_table, src1_name);
    ln_opck_tensor_defined(src1_entry, src1_name);
    src1 = src1_entry->tensor;
    src1 = src1;

    src2_list_entry = ln_tensor_list_find_by_arg_name(op_arg->tensors_in, "src2");
    ln_opck_tensor_in_exist(src2_list_entry, "src2");
    src2_name = src2_list_entry->name;
    src2_entry = ln_tensor_table_find(op_arg->tensor_table, src2_name);
    ln_opck_tensor_defined(src2_entry, src2_name);
    src2 = src2_entry->tensor;
    src2 = src2;
    ln_opck_tensor_issametype(src2_entry, src1_entry);

    tensors_out_n = ln_tensor_list_length(op_arg->tensors_out);
    ln_opck_tensors_out_len_eq(tensors_out_n, 1);

    dst_list_entry = ln_tensor_list_find_by_arg_name(op_arg->tensors_out, "dst");
    ln_opck_tensor_out_exist(dst_list_entry, "dst");
    dst_name = dst_list_entry->name;
    dst_entry = ln_tensor_table_find(op_arg->tensor_table, dst_name);
    ln_opck_tensor_not_defined(dst_entry, dst_name);

    params_n = ln_param_list_length(op_arg->params);
    ln_opck_params_len_eq(params_n, 1);

    axis_entry = ln_param_list_find(op_arg->params, "axis");
    ln_opck_param_exist(axis_entry, "axis");
    ln_opck_param_type(axis_entry, LN_PARAM_NUMBER);
    axis = axis_entry->value_int;
    axis = axis;
    {
        {
            char shape1[LN_MAXLINE];
            char shape2[LN_MAXLINE];
            ln_opck_satisfy_msg(axis >= 0 && axis < src1->ndim, "`axis` %d should match the dimensions of `src1` (%s )and `src2` (%d)", axis, ln_sprint_shape(shape1, src1->ndim, src1->dims), ln_sprint_shape(shape2, src2->ndim, src2->dims));
        }
    }

    {
        for (int i = 0; i < src1->ndim; i++) {
            if (i == axis)
                continue;
            char shape1[LN_MAXLINE];
            char shape2[LN_MAXLINE];
            ln_opck_satisfy_msg(src1->dims[i] == src2->dims[i], "`src1` (%s) and `src2` (%s) should have the same shape, except in the dimension corresponding to `axis` %d", ln_sprint_shape(shape1, src1->ndim, src1->dims), ln_sprint_shape(shape2, src2->ndim, src2->dims), axis);
        }
    }

    /* define output tensor shape, tensor data should be NULL */
    dst_ndim = src1->ndim;
    dst_dtype = src1->dtype;
    {
        dst_dims = ln_clone(src1->dims, sizeof(int)*src1->ndim);
        dst_dims[axis] = src1->dims[axis] + src2->dims[axis];
    }
    dst = tl_tensor_create(NULL, dst_ndim, dst_dims, dst_dtype);
    dst_entry = ln_tensor_entry_create(dst_name, dst);
    dst_entry->offset = dst_list_entry->offset;
    ln_tensor_entry_set_creater(dst_entry, op_arg->name);
    dst_entry->mtype = LN_MEM_NONE;
    ln_tensor_table_insert(op_arg->tensor_table, dst_entry);
    {
        ln_free(dst_dims);
    }

    /* use op_arg->priv to store private data to be used in other functions */
    priv = ln_alloc(sizeof(struct priv_s));
    priv->src1_entry = src1_entry;
    priv->src2_entry = src2_entry;
    priv->dst_entry = dst_entry;
    priv->axis_entry = axis_entry;
    op_arg->priv = priv;
}

/* This function should free all the memory allocated by other *_run()s. */
static void concat_post_run(ln_op_arg *op_arg)
{
    struct priv_s *priv = op_arg->priv;

    ln_tensor_table_remove(op_arg->tensor_table, priv->dst_entry->name);
    ln_free(priv);
}

static const char *in_arg_names[] = {
    "src1",
    "src2",
    NULL
};

static const char *out_arg_names[] = {
    "dst",
    NULL
};

static const char *param_arg_names[] = {
    "axis",
    NULL
};

static const ln_param_type param_ptypes[] = {
    LN_PARAM_NUMBER,
};

/* specify other ln_op_arg fields */
static ln_op_arg op_arg_concat = {
    .optype = "concat",
    .arch = "none",
    .in_arg_names = in_arg_names,
    .out_arg_names = out_arg_names,
    .param_arg_names = param_arg_names,
    .param_ptypes = param_ptypes,
};

/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_concat = {
    .op_arg = &op_arg_concat,
    .pre_run = concat_pre_run,
    .static_run = NULL,
    .run = NULL,
    .post_run = concat_post_run
};
