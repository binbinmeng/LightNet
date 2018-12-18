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

#include <assert.h>
#include "ln_op.h"
#include "ln_cuda.h"

struct priv_s {
    ln_tensor_entry *src_entry;
    ln_tensor_entry *dst_entry;
    ln_param_entry  *mode_entry;
    ln_param_entry  *scales_entry;
};

/* This function should do the parameter checking and tensor shape inference. */
static void upsample_cuda_pre_run(ln_op_arg *op_arg)
{
    char                 *src_name;
    ln_tensor_list_entry *src_list_entry;
    ln_tensor_entry      *src_entry;
    tl_tensor            *src;
    char                 *dst_name;
    ln_tensor_list_entry *dst_list_entry;
    ln_tensor_entry      *dst_entry;
    tl_tensor            *dst;
    int                   dst_ndim;
    int                  *dst_dims;
    tl_dtype              dst_dtype;
    int                   mode;
    ln_param_entry       *mode_entry;
    float                *scales;
    ln_param_entry       *scales_entry;
    int                   tensors_in_n;
    int                   tensors_out_n;
    int                   params_n;
    struct priv_s        *priv;

    /* check tensors and parameters */
    tensors_in_n = ln_tensor_list_length(op_arg->tensors_in);
    ln_opck_tensors_in_len_eq(tensors_in_n, 1);

    src_list_entry = ln_tensor_list_find_by_arg_name(op_arg->tensors_in, "src");
    ln_opck_tensor_in_exist(src_list_entry, "src");
    src_name = src_list_entry->name;
    src_entry = ln_tensor_table_find(op_arg->tensor_table, src_name);
    ln_opck_tensor_defined(src_entry, src_name);
    src = src_entry->tensor;
    src = src;
    ln_opck_tensor_mtype_eq(src_entry, LN_MEM_CUDA);

    tensors_out_n = ln_tensor_list_length(op_arg->tensors_out);
    ln_opck_tensors_out_len_eq(tensors_out_n, 1);

    dst_list_entry = ln_tensor_list_find_by_arg_name(op_arg->tensors_out, "dst");
    ln_opck_tensor_out_exist(dst_list_entry, "dst");
    dst_name = dst_list_entry->name;
    dst_entry = ln_tensor_table_find(op_arg->tensor_table, dst_name);
    ln_opck_tensor_not_defined(dst_entry, dst_name);

    params_n = ln_param_list_length(op_arg->params);
    ln_opck_params_len_eq(params_n, 2);

    mode_entry = ln_param_list_find(op_arg->params, "mode");
    ln_opck_param_exist(mode_entry, "mode");
    ln_opck_param_type(mode_entry, LN_PARAM_STRING);
    mode = tl_resize_type_from_str(mode_entry->value_string);
    mode_entry->value_int = mode;
    mode = mode;
    ln_opck_satisfy_msg(mode != -1, "`mode` should be 'TL_NEAREST' or 'TL_LINEAR'");

    scales_entry = ln_param_list_find(op_arg->params, "scales");
    ln_opck_param_exist(scales_entry, "scales");
    ln_opck_param_type(scales_entry, LN_PARAM_ARRAY_NUMBER);
    scales = scales_entry->value_array_float;
    ln_opck_param_array_float_gt(scales_entry, 0);
    scales = scales;
    ln_opck_satisfy_msg(scales_entry->array_len == src->ndim, "the length of `scales` should be the same as the rank of input `src`");

    /* define output tensor shape, tensor data should be NULL */
    dst_ndim = src->ndim;
    dst_dtype = src->dtype;
    {
        dst_dims = ln_alloc(sizeof(int)*dst_ndim);
        for (int i = 0; i < dst_ndim; i++)
            dst_dims[i] = (int)floorf(scales[i] * src->dims[i]);
    }
    dst = tl_tensor_create(NULL, dst_ndim, dst_dims, dst_dtype);
    dst_entry = ln_tensor_entry_create(dst_name, dst);
    ln_tensor_entry_set_creater(dst_entry, op_arg->name);
    dst_entry->mtype = LN_MEM_CUDA;
    ln_tensor_table_insert(op_arg->tensor_table, dst_entry);
    {
        ln_free(dst_dims);
    }

    /* use op_arg->priv to store private data to be used in other functions */
    priv = ln_alloc(sizeof(struct priv_s));
    priv->src_entry = src_entry;
    priv->dst_entry = dst_entry;
    priv->mode_entry = mode_entry;
    priv->scales_entry = scales_entry;
    op_arg->priv = priv;
}

/* This function should only do the calculations. */
static void upsample_cuda_run(ln_op_arg *op_arg)
{
    struct priv_s *priv = op_arg->priv;
    tl_tensor     *src = priv->src_entry->tensor;
    tl_tensor     *dst = priv->dst_entry->tensor;
    int            mode = priv->mode_entry->value_int;

    {
        tl_tensor_resize_cuda(src, dst, dst->dims, mode);
    }
}

/* This function should free all the memory allocated by other *_run()s. */
static void upsample_cuda_post_run(ln_op_arg *op_arg)
{
    struct priv_s *priv = op_arg->priv;

    ln_tensor_table_remove(op_arg->tensor_table, priv->dst_entry->name);
    ln_free(priv);
}

static const char *in_arg_names[] = {
    "src",
    NULL
};

static const char *out_arg_names[] = {
    "dst",
    NULL
};

static const char *param_arg_names[] = {
    "mode",
    "scales",
    NULL
};

/* specify other ln_op_arg fields */
static ln_op_arg op_arg_upsample_cuda = {
    .optype = "upsample_cuda",
    .arch = "cuda",
    .in_arg_names = in_arg_names,
    .out_arg_names = out_arg_names,
    .param_arg_names = param_arg_names,
};

/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_upsample_cuda = {
    .op_arg = &op_arg_upsample_cuda,
    .pre_run = upsample_cuda_pre_run,
    .static_run = NULL,
    .run = upsample_cuda_run,
    .post_run = upsample_cuda_post_run
};
