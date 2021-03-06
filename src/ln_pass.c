/*
 * Copyright (c) 2018-2019 Zhao Zhixu
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
#include "ln_pass.h"

const int MAX_PEEPHOLE_PASSES = 10;

static int is_tensors_static(const ln_list *tensors, ln_hash *table)
{
    ln_tensor_list_entry *tle;
    ln_tensor_entry *te;

    LN_LIST_FOREACH(tle, tensors) {
        te = ln_tensor_table_find(table, tle->name);
        if (!te->isstatic)
            return 0;
    }
    return 1;
}

static ln_list **last_tensors_defination(ln_context *ctx, ln_list *tensors)
{
    ln_op *op;
    ln_list **pos = NULL;
    ln_list *l;
    ln_tensor_entry *te1, *te2;
    int len;

    if (!tensors)
        return &ctx->ops;

    len = ln_list_length(tensors);
    for (l = ctx->ops; l; l = l->next) {
        op = l->data;
        LN_LIST_FOREACH(te1, op->op_arg->tensors_out) {
            LN_LIST_FOREACH(te2, tensors) {
                if (ln_streq(te1->name, te2->name)) {
                    if (--len == 0) {
                        pos = &l->next;
                        goto end;
                    }
                }
            }
        }
    }
end:
    return pos;
}

void ln_pass_preprocess(ln_context *ctx)
{
    ln_list **lp;
    ln_list **pos;
    ln_op *op;
    ln_op *op_copy;
    ln_tensor_list_entry *tle;
    ln_tensor_entry *te;

    /* move all ops without tensors_in or with static tensors_in and with static
       tensors_out to the beginning of ops */
    for (lp = &ctx->ops; *lp;) {
        op = (*lp)->data;
        if (lp == &ctx->ops)    /* skip the first op */
            goto no_move;
        if (!op->op_arg->tensors_in ||
            is_tensors_static(op->op_arg->tensors_in,
                              op->op_arg->tensor_table)) {
            LN_LIST_FOREACH(tle, op->op_arg->tensors_out) {
                te = ln_tensor_table_find(op->op_arg->tensor_table, tle->name);
                if (!te->isstatic)
                    goto no_move;
            }
            op_copy = ln_op_copy(op);
            ln_context_remove_op(ctx, lp);
            pos = last_tensors_defination(ctx, op_copy->op_arg->tensors_in);
            ln_context_add_op(ctx, pos, op_copy);
            continue;
        }
    no_move:
        lp = &(*lp)->next;
    }
    ln_context_check(ctx);
}

void ln_pass_expander(ln_context *ctx, const ln_expander_func *ep_funcs)
{
    ln_op *op;
    ln_list **lp;
    ln_list *ep_ops;
    ln_expander_func ep_func;
    int match;
    int i;

    ep_ops = NULL;
    for (lp = &ctx->ops; *lp; lp = &(*lp)->next) {
        op = (*lp)->data;
        for (i = 0; (ep_func = ep_funcs[i]); i++) {
            match = 0;
            ep_ops = ep_func(op, ctx->dfg, &match);
            if (!match)
                continue;
            ln_context_replace_ops(ctx, lp, 1, ep_ops);
            ln_context_check(ctx);
        }
    }
}

void ln_pass_combiner(ln_context *ctx, size_t win_size,
                      const ln_combiner_func *cb_funcs)
{
    ln_combiner_func cb;
    ln_list *win_out;
    ln_list **lp;
    int stable = 0;
    int count = 0;
    int match;
    int i;

    while (!stable) {
        stable = 1;
        for (lp = &ctx->ops; *lp; lp = &(*lp)->next) {
            if (ln_list_length(*lp) < win_size)
                break;
            for (i = 0; (cb = cb_funcs[i]); i++) {
                match = 0;
                win_out = cb(*lp, win_size, ctx->dfg, &match);
                if (!match)
                    continue;
                stable = 0;
                ln_context_replace_ops(ctx, lp, win_size, win_out);
                ln_context_check(ctx);
            }
        }
        if (++count > MAX_PEEPHOLE_PASSES) {
            ln_msg_emit(LN_MSG_INTER_WARN,
                          "peephole passes exceeds limit of %d",
                          MAX_PEEPHOLE_PASSES);
        }
    }
}

static inline void use_count_zero(ln_hash *use_counts, char *name)
{
    ln_hash_insert(use_counts, name, (void *)0);
}

static inline ssize_t use_count_inc(ln_hash *use_counts, char *name)
{
    int found;
    ssize_t uc;

    found = ln_hash_find_extended(use_counts, name, NULL, (void **)&uc);
    assert(found);
    ln_hash_insert(use_counts, name, (void *)(++uc));
    return uc;
}

static inline ssize_t use_count_dec(ln_hash *use_counts, char *name)
{
    int found;
    ssize_t uc;

    found = ln_hash_find_extended(use_counts, name, NULL, (void **)&uc);
    assert(found);
    ln_hash_insert(use_counts, name, (void *)(--uc));
    assert(uc >= 0);
    return uc;
}

static inline ssize_t use_count_of(ln_hash *use_counts, char *name)
{
    int found;
    ssize_t uc;

    found = ln_hash_find_extended(use_counts, name, NULL, (void **)&uc);
    assert(found);
    return uc;
}

void ln_pass_mem_pool(ln_context *ctx)
{
    ln_op *op;
    ln_op_arg *arg;
    ln_hash *use_counts;
    ln_tensor_entry *te;
    ln_tensor_entry *owner_te;
    ln_tensor_list_entry *tle;
    ln_hash *mem_pools;
    ln_mem_pool *mp;
    ln_list *unused_tles;
    size_t total_sums[LN_MEM_TYPE_SIZE] = {0};
    size_t water_level;

    mem_pools = ln_mem_pool_table_create();
    use_counts = ln_hash_create(ln_str_hash, ln_str_cmp, NULL, NULL);
    LN_LIST_FOREACH(op, ctx->ops) {
        arg = op->op_arg;
        LN_LIST_FOREACH(tle, arg->tensors_out) {
            te = ln_tensor_table_find(arg->tensor_table, tle->name);
            mp = ln_hash_find(mem_pools, (void *)te->mtype);
            if (te->mtype == LN_MEM_NONE)
                ln_msg_inter_error("tensor '%s' has an unresolved memory type %s",
                                   te->name, ln_mem_type_name(te->mtype));
            if (te->owner)
                continue;
            if (te->isstatic) {
                te->offset = ln_mem_pool_alloc(mp, tl_tensor_size(te->tensor));
                water_level = te->offset + tl_tensor_size(te->tensor);
                ctx->mem_sizes[te->mtype] =
                    ctx->mem_sizes[te->mtype] > water_level ?
                    ctx->mem_sizes[te->mtype] : water_level;
                total_sums[te->mtype] += tl_tensor_size(te->tensor);
                ln_msg_debug("plan memory %s: %s %lu bytes at offset %p",
                               ln_mem_type_name(te->mtype), tle->name,
                               tl_tensor_size(te->tensor), te->offset);
                use_count_zero(use_counts, te->name);
                continue;
            }
            if (ln_hash_find_extended(use_counts, te->name, NULL, NULL))
                use_count_inc(use_counts, te->name);
            else
                use_count_zero(use_counts, te->name);
        }
        LN_LIST_FOREACH(tle, arg->tensors_in) {
            te = ln_tensor_table_find(arg->tensor_table, tle->name);
            if (te->owner) {
                use_count_inc(use_counts, te->owner);
                continue;
            }
            /* if (te->isstatic) */
            /*     continue; */
            use_count_inc(use_counts, te->name);
        }
    }

    LN_LIST_FOREACH(op, ctx->ops) {
        arg = op->op_arg;
        unused_tles = NULL;
        LN_LIST_FOREACH(tle, arg->tensors_out) {
            te = ln_tensor_table_find(arg->tensor_table, tle->name);
            mp = ln_hash_find(mem_pools, (void *)te->mtype);
            if (te->owner) {
                owner_te = ln_tensor_table_find(arg->tensor_table, te->owner);
                assert(owner_te);
                te->offset = owner_te->offset;
                ln_msg_debug("plan memory %s: %s %lu bytes at offset %p",
                               ln_mem_type_name(te->mtype), tle->name,
                               tl_tensor_size(te->tensor), te->offset);
                continue;
            }
            if (te->isstatic)
                continue;
            if (ln_mem_pool_exist(mp, te->offset)) {
                use_count_dec(use_counts, te->name);
            } else {
                te->offset = ln_mem_pool_alloc(mp, tl_tensor_size(te->tensor));
                water_level = te->offset + tl_tensor_size(te->tensor);
                ctx->mem_sizes[te->mtype] =
                    ctx->mem_sizes[te->mtype] > water_level ?
                    ctx->mem_sizes[te->mtype] : water_level;
                total_sums[te->mtype] += tl_tensor_size(te->tensor);
                ln_msg_debug("plan memory %s: %s %lu bytes at offset %p",
                               ln_mem_type_name(te->mtype), tle->name,
                               tl_tensor_size(te->tensor), te->offset);
            }
            if (use_count_of(use_counts, te->name) == 0)
                unused_tles = ln_list_prepend(unused_tles, tle);
        }
        LN_LIST_FOREACH(tle, unused_tles) {
            te = ln_tensor_table_find(arg->tensor_table, tle->name);
            mp = ln_hash_find(mem_pools, (void *)te->mtype);
            ln_mem_pool_dealloc(mp, te->offset);
        }
        ln_list_free(unused_tles);
        LN_LIST_FOREACH(tle, arg->tensors_in) {
            te = ln_tensor_table_find(arg->tensor_table, tle->name);
            mp = ln_hash_find(mem_pools, (void *)te->mtype);
            if (te->owner) {
                if (use_count_dec(use_counts, te->owner) == 0) {
                    te = ln_tensor_table_find(arg->tensor_table, te->owner);
                    if (te->isstatic)
                        continue;
                    ln_mem_pool_dealloc(mp, te->offset);
                }
                continue;
            }
            if (te->isstatic) {
                use_count_dec(use_counts, te->name);
                continue;
            }
            if (use_count_dec(use_counts, te->name) == 0) {
                ln_mem_pool_dealloc(mp, te->offset);
            }
        }
    }
    assert(ctx->mem_sizes[LN_MEM_NONE] == 0);

#ifdef LN_DEBUG
    for (int i = LN_MEM_NONE+1; i < LN_MEM_TYPE_SIZE; i++) {
        ln_msg_debug("planned usage of memory %s: %lu bytes",
                       ln_mem_type_name(i), ctx->mem_sizes[i]);
        ln_msg_debug("counted usage of memory %s: %lu bytes",
                       ln_mem_type_name(i), total_sums[i]);
    }
#endif  /* LN_DEBUG */

    ln_hash_free(use_counts);
    ln_mem_pool_table_free(mem_pools);
}
