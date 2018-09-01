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

#include "test_lightnet.h"
#include "../src/ln_util.h"
#include "../src/ln_list.h"

static int *data;
static size_t data_len;
static ln_list *list;

static void free_int(int *i)
{
     free(i);
}

static void free_int_wrapper(void *p)
{
     free_int(p);
}

static void setup(void)
{
     int i;
     list = ln_list_create();
     data_len = 5;
     data = ln_alloc(sizeof(int) * data_len);
     for (i = 0; i < 5; i++) {
          data[i] = i;
          ln_list_append(list, &data[i]);
     }
}

static void teardown(void)
{
     ln_free(data);
     ln_list_free(list);
}

static int cmp(void *p1, void *p2)
{
     return *(int *)p1 - *(int *)p2;
}

START_TEST(test_ln_list_append_nth)
{
     ln_list *l = ln_list_create();

     ln_list_append(l, &data[0]);
     ln_list_append(l, &data[1]);
     ck_assert_int_eq(*(int *)ln_list_nth_data(l, 0), 0);
     ck_assert_int_eq(*(int *)ln_list_nth_data(l, 1), 1);
     ln_list_free(l);
}
END_TEST

START_TEST(test_ln_list_remove)
{
     int num, i;

     list = ln_list_remove(list, &data[0]);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 0), 1);

     ln_list_insert_nth(list, &data[0], 0);
     ln_list_remove(list, &data[4]);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 3), 3);
     ck_assert_ptr_eq(ln_list_nth_data(list, 4), NULL);

     ln_list_insert_nth(list, &data[4], 4);
     num = -1;
     ln_list_remove(list, &num);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);

     num = 5;
     ln_list_remove(list, &num);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);
}
END_TEST

START_TEST(test_ln_list_remove_custom)
{
     int num, i;

     ln_list_remove_custom(list, &data[0], cmp);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 0), 1);

     ln_list_insert_nth(list, &data[0], 0);
     ln_list_remove_custom(list, &data[4], cmp);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 3), 3);
     ck_assert_ptr_eq(ln_list_nth_data(list, 4), NULL);

     ln_list_insert_nth(list, &data[4], 4);
     num = -1;
     list = ln_list_remove_custom(list, &num, cmp);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);

     num = 5;
     ln_list_remove_custom(list, &num, cmp);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);

}
END_TEST

START_TEST(test_ln_list_remove_insert_nth)
{
     int i;

     ln_list_remove_nth(list, 2);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 2), 3);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 1), 1);

     ln_list_insert_nth(list, &data[2], 2);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 2), 2);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 3), 3);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 1), 1);

     ln_list_remove_nth(list, 0);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 0), 1);

     ln_list_insert_nth(list, &data[0], 0);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 0), 0);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 1), 1);

     ln_list_remove_nth(list, 4);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 3), 3);
     ck_assert_ptr_eq(ln_list_nth_data(list, 4), NULL);

     ln_list_insert_nth(list, &data[4], 4);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 4), 4);
     ck_assert_int_eq(*(int *)ln_list_nth_data(list, 3), 3);

     ln_list_remove_nth(list, -1);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);

     ln_list_remove_nth(list, 6);
     for (i = 0; i < data_len; i++)
          ck_assert_int_eq(*(int *)ln_list_nth_data(list, i), data[i]);
}
END_TEST

START_TEST(test_ln_list_find)
{
     int n1 = 6;
     int n2 = -1;
     void *p;

     p = ln_list_find(list, &data[3]);
     ck_assert_int_eq(*(int *)p, data[3]);

     p = ln_list_find(list, &n1);
     ck_assert_ptr_eq(p, NULL);

     p = ln_list_find(list, &n2);
     ck_assert_ptr_eq(p, NULL);
}
END_TEST

START_TEST(test_ln_list_find_custom)
{
     int n1 = 6;
     int n2 = -1;
     void *p;

     p = ln_list_find_custom(list, &data[3], &cmp);
     ck_assert_int_eq(*(int *)p, data[3]);

     p = ln_list_find_custom(list, &n1, &cmp);
     ck_assert_ptr_eq(p, NULL);

     p = ln_list_find_custom(list, &n2, &cmp);
     ck_assert_ptr_eq(p, NULL);
}
END_TEST

/* START_TEST(test_ln_list_position) */
/* { */
/*      int pos; */
/*      ln_list *l; */

/*      pos = ln_list_position(list, list->next); */
/*      ck_assert_int_eq(pos, 1); */

/*      l = (ln_list *)ln_alloc(sizeof(ln_list)); */
/*      pos = ln_list_position(list, l); */
/*      ck_assert_int_eq(pos, -1); */

/*      pos = ln_list_position(list, NULL); */
/*      ck_assert_int_eq(pos, -1); */
/* } */
/* END_TEST */

START_TEST(test_ln_list_index)
{
     int pos;
     int n;

     pos = ln_list_index(list, list->head->next->data);
     ck_assert_int_eq(pos, 1);

     n = 6;
     pos = ln_list_index(list, &n);
     ck_assert_int_eq(pos, -1);
}
END_TEST

START_TEST(test_ln_list_index_custom)
{
     int pos;
     int n;

     pos = ln_list_index_custom(list, list->head->next->data, cmp);
     ck_assert_int_eq(pos, 1);

     n = 6;
     pos = ln_list_index_custom(list, &n, cmp);
     ck_assert_int_eq(pos, -1);
}
END_TEST


START_TEST(test_ln_list_length)
{
     ln_list *l;
     int data;

     l = ln_list_create();
     data = 0;
     ck_assert_int_eq(ln_list_length(l), 0);
     l = ln_list_append(l, &data);
     ck_assert_int_eq(ln_list_length(l), 1);
     ck_assert_int_eq(ln_list_length(list), 5);
}
END_TEST

START_TEST(test_ln_list_from_array_size_t)
{
     ln_list *l;
     size_t i;
     size_t array[3];

     for (i = 0; i < 3; i++)
          array[i] = i;
     l = ln_list_from_array_size_t(NULL, 0);
     ck_assert_int_eq(l->len, 0);
     l = ln_list_from_array_size_t(array, 3);
     for (i = 0; i < 3; i++) {
          ck_assert_int_eq((size_t)ln_list_nth_data(l, i), i);
     }
}
END_TEST

START_TEST(test_ln_list_free_deep)
{
     ln_list *l;
     int *int1, *int2;

     int1 = ln_alloc(sizeof(int));
     int2 = ln_alloc(sizeof(int));
     *int1 = 1;
     *int2 = 2;
     l = ln_list_create();
     l = ln_list_append(l, int1);
     l = ln_list_append(l, int2);
     ln_list_free_deep(l, free_int_wrapper);
}
END_TEST
/* end of tests */

Suite *make_list_suite(void)
{
     Suite *s;
     s = suite_create("list");

     TCase *tc_list;
     tc_list = tcase_create("tc_list");
     tcase_add_checked_fixture(tc_list, setup, teardown);

     tcase_add_test(tc_list, test_ln_list_append_nth);
     tcase_add_test(tc_list, test_ln_list_remove);
     tcase_add_test(tc_list, test_ln_list_remove_custom);
     tcase_add_test(tc_list, test_ln_list_remove_insert_nth);
     tcase_add_test(tc_list, test_ln_list_find);
     tcase_add_test(tc_list, test_ln_list_find_custom);
     /* tcase_add_test(tc_list, test_ln_list_position); */
     tcase_add_test(tc_list, test_ln_list_index);
     tcase_add_test(tc_list, test_ln_list_index_custom);
     tcase_add_test(tc_list, test_ln_list_length);
     tcase_add_test(tc_list, test_ln_list_from_array_size_t);
     tcase_add_test(tc_list, test_ln_list_free_deep);
     /* end of adding tests */

     suite_add_tcase(s, tc_list);

     return s;
}
