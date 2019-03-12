#! /usr/bin/env perl

package testgl;

use 5.014;
use warnings;
use strict;
use JSON;
use File::Copy;
use Cwd 'abs_path';
use Getopt::Long;
use Scalar::Util qw(reftype);
use File::Path qw(make_path);
use File::Basename;
use lib abs_path(dirname(__FILE__));
use util;
use easyjson;
use constant HASH => ref {};
use constant ARRAY => ref [];
use constant CODE => ref sub{};
no warnings 'experimental::smartmatch';

my %global_ops;
my %basic_types = (double=>1, float=>1, int=>1, "char *"=>1, ln_bool=>1);
my %array_types = ("double *"=>1, "float *"=>1, "int *"=>1, "char **"=>1, "ln_bool *"=>1);
my $directive_p = qr/\$\{[a-zA-Z0-9_-]+\s+ .+\}/;
my $symbol_p = qr/[a-zA-Z0-9.,\[\]()_"\\\$\@\^]+/;

my $usage = <<EOF;
Usage: $0 [OPTION] [JSON_FILE(s)]
Generate expander code from expander description JSON.
Read the JSON string from standard input if JSON_FILE(s) are not given.
Print the output code to standard output if --dir and --root are omited.

Options:
  -h, --help              print this message
  -d, --dir=DIRECTORY     save expander file(s) in DIRECTORY
  -r, --root=ROOT         set project root directory; this option will save
                          expanders file(s) in ROOT/src/arch/auto, and add
                          expander declarations and such to
                          ROOT/src/arch/ln_archimpl_*.c
Author: Zhao Zhixu
EOF

my $INDENT_OFFSET = 4;

my $root = '';
my $dir = '';
GetOptions(
           'help' => sub {&exit_msg(0, $usage)},
           'dir=s' => \$dir,
           'root=s' => \$root,
          ) or &exit_msg(1, $usage);

my @json_files = @ARGV;
if (@json_files == 0) {
    my $json_text = join '', <STDIN>;
    my $json = &read_json_text($json_text);
    &gen_code($json);
} else {
    foreach my $file (@json_files) {
        my $json = &read_json($file);
        &gen_code($json);
    }
}

sub gen_code {
    my $json = shift;

    &err_exit("JSON needs an 'arch'") unless exists $json->{arch};
    &err_exit("JSON needs an 'name'") unless exists $json->{name};
    &err_exit("JSON needs an 'author'") unless exists $json->{author};
    &err_exit("JSON needs an 'ops'") unless exists $json->{ops};
    my $arch = $json->{arch};
    my $name = $json->{name};
    my $author = $json->{author};
    my $ops = $json->{ops};

    my @blocks = ();
    push @blocks, &gen_head_block($arch, $author);
    my @ep_funcs = ();
    foreach my $op (@$ops) {
        push @blocks, &gen_expander($op, \@ep_funcs);
    }
    push @blocks, &gen_ep_funcs(\@ep_funcs);
    push @blocks, &gen_overall_funcs($name);

    my $c_code_str = join "\n", @blocks;
    if (not $dir and not $root) {
        print $c_code_str;
    }
    if ($dir) {
        unless (-d $dir) {
            make_path($dir, {mode => 0755})
                or die "Cannot create directory $dir: $!";
        }
        my $dir_file = "${dir}/ln_expander_${name}.c";
        &backup_write($dir_file, $c_code_str);
    }
    if ($root) {
        unless (-d "${root}/src/arch/auto") {
            make_path("${root}/src/arch/auto", {mode => 0755})
                or die "Cannot create directory ${root}/src/arch/auto: $!";
        }
        my $src_file = "${root}/src/arch/auto/ln_expander_${name}.c";
        &backup_write($src_file, $c_code_str);
        my $arch_file = "${root}/src/arch/ln_archimpl_${arch}.c";
        &add_to_arch_file($arch_file, $arch, $name);
    }
}

sub gen_head_block {
    my $arch = shift;
    my $author = shift;
    my $head_block_tpl = <<EOF;
/*
 * Copyright (c) 2019 $author
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

 #include "ln_arch.h"
 #include "ln_name.h"
 #include "ln_$arch.h"
EOF
}

sub gen_expander {
    my $op = shift;
    my $ep_funcs = shift;
    &err_exit("needs a 'optype'") unless exists $op->{optype};
    my $optype = $op->{optype};
    &err_exit("'${optype}' needs a 'rules'") unless exists $op->{rules};
    my $rules = $op->{rules};

    my @auto_vars = ();
    my @rules_codes;
    my $found_default = 0;
    foreach my $rule (@$rules) {
        &err_exit("needs a 'cond'") unless exists $rule->{cond};
        $found_default = 1 if @{$rule->{cond}} == 0;
        my %defined_ops = (self => $optype);
        my $cond_code = &gen_cond($rule->{cond}, \%defined_ops);

        my @new_op_codes;
        my @body_codes;
        if (exists $rule->{warn}) {
            push @body_codes, "ln_msg_inter_warn(\"ep_$optype(): $rule->{warn}\");";
        }

        if (exists $rule->{replace}) {
            foreach (@{$rule->{replace}}) {
                my ($type, $name) = split;
                if (defined $name) {
                    $defined_ops{$name} = $type;
                }
            }
            push @body_codes, &gen_replace($rule->{replace}, $rule->{details},
                                           \@auto_vars, \%defined_ops);
        } elsif (exists $rule->{err}) {
            push @body_codes, <<EOF;
ln_msg_inter_error("ep_$optype(): $rule->{err}");
return NULL;
EOF
        } elsif (exists $rule->{match} and not $rule->{match}) {
            push @body_codes, "*match = 0;\nreturn NULL;";
        } else {
            &err_exit("optype '$optype' needs a 'replace' or 'match' or 'err'");
        }

        my $body_code = &indent_block($INDENT_OFFSET, (join "\n", @body_codes));
        if ($rule == $rules->[0]) {
            push @rules_codes, <<EOF;
if ($cond_code) {
$body_code
}
EOF
        } else {
            push @rules_codes, <<EOF;
else if ($cond_code) {
$body_code
}
EOF
        }
    }
    &warn_msg("default conditions (\"cond\": []) not found in optype '$optype'")
        unless $found_default;

    &make_defs_neat(\@auto_vars);
    my $auto_vars_code = join "\n", &indent_lines($INDENT_OFFSET, \@auto_vars);
    my $rules_code = &indent_block($INDENT_OFFSET, (join "\n", @rules_codes));

    push @$ep_funcs, "{\"$optype\", ep_$optype},";
    my $tpl = <<EOF;
static ln_list *ep_$optype(const ln_op *self, const ln_dfg *dfg, int *match)
{
    /* auto variables */
$auto_vars_code

   /* replace self with new ops */
$rules_code
}
EOF
}

sub gen_cond {
    my $conds = shift;
    my $defined_ops = shift;

    return "1" if @$conds == 0;
    my $cond_code;
    my @conds_replaced;
    foreach my $cond (@$conds) {
        $cond = &do_rh($cond, $defined_ops);
        while ($cond =~ /($symbol_p)\s*(=>)\s*($symbol_p)?/g) {
            $cond_code = (&expand_op_str($&, $defined_ops))[1];
            my $pos_bak = pos($cond);
            substr($cond, pos($cond)-length($&), length($&)) = $cond_code;
            pos($cond) = $pos_bak-length($&)+length($cond_code);
        }
        while ($cond =~ /(($symbol_p)\s*(>|>=|<|<=|==|!=)\s*($symbol_p))/g) {
            my $operator = $3;
            my $lhs = $2;
            my $rhs = $4;
            my ($l_type, $l_code, $l_len) = &expand_op_str($lhs, $defined_ops);
            my ($r_type, $r_code, $r_len) = &expand_op_str($rhs, $defined_ops);
            my $type = &type_converse($l_type, $r_type);
            if (not defined $type) {
                &warn_msg("both operands' types are undefined in '$1', using literal string '$1'");
                $cond_code = $1;
                next;
            } elsif (not $type) {
                &err_exit("unmatched type '$l_type' and '$r_type' in '$1'");
            }

            &err_exit("unmatched operand lengths '$l_len' and '$r_len' in '$1'")
                if ((defined $l_len or defined $r_len) and $l_len != $r_len);
            $cond_code = &gen_comparator($operator, $l_code, $r_code, $type, $l_len);
            my $pos_bak = pos($cond);
            substr($cond, pos($cond)-length($&), length($&)) = $cond_code;
            pos($cond) = $pos_bak-length($&)+length($cond_code);
        }
        push @conds_replaced, "($cond)";
    }
    join " ||\n    ", @conds_replaced;
}

sub gen_comparator {
    my $op = shift;
    my $lhs = shift;
    my $rhs = shift;
    my $type = shift;
    my $len = shift;

    my $code;
    given ($op) {
        when (/>|>=|<|<=|==|!=/) {
            given ($type) {
                when ("char *") {
                    $code = "(strcmp($lhs, $rhs) $op 0)"
                }
                when ("char **") {
                    $code = <<EOF;
({
    int result = 1;
    for (int i = 0; i < $len; i++) {
        if (!(strcmp(${lhs}[i], ${rhs}[i]) $op 0)) {
            result = 0;
            break;
        }
    }
    result;
})
EOF
                }
                when (/^(int|float|double|ln_bool) \*$/) {
                    $code = <<EOF;
({
    int result = 1;
    for (int i = 0; i < $len; i++) {
        if (!({lhs}[i] $op ${rhs}[i])) {
            result = 0;
            break;
        }
    }
    result;
})
EOF
                }
                when (/^(int|float|double|ln_bool|ln_mem_type)$/) {
                    $code = "($lhs $op $rhs)";
                }
                default {
                    $code = "($lhs $op $rhs)";
                    &warn_msg("'$type' uses default comparator '$code'");
                }
            }
        }
        default {
            &err_exit("'$op' is not a comparator operator");
        }
    }
    $code;
}

sub gen_replace {
    my $replace = shift;
    my $details = shift;
    my $auto_vars = shift;
    my $defined_ops = shift;

    my $optype = $defined_ops->{self};
    my $desc = &find_op_desc($optype);
    my $code;
    if (not defined $details) {
        &err_exit("need a 'details' to replace with multiple operators") if (@$replace != 1);
        my $rep_optype = (split ' ', $replace->[0])[0];
        my $rep_desc = &find_op_desc($rep_optype);
        # TODO: check validation
        $code = <<EOF;
ln_op *new_op = ln_op_copy_to_optype(LN_ARCH.op_proto_table, self, "$rep_optype");
return ln_list_append(NULL, new_op);
EOF
        chomp $code;
        return $code;
    }

    my @blocks;
    push @blocks, "ln_op *op_proto;";
    push @blocks, "ln_list *new_ops = NULL;";
    push @blocks, "";
    foreach (@$replace) {
        my ($type, $name) = split;
        &err_exit("replace details needs a list of new op types and names: '$_'")
            if not defined $type or not defined $name;
        my $create_op = <<EOF;
op_proto = ln_hash_find(LN_ARCH.op_proto_table, "$type");
assert(op_proto);
ln_op *$name = ln_op_create_with_names(op_proto, self->op_arg->tensor_table);
new_ops = ln_list_append(new_ops, $name);
EOF
        push @blocks, $create_op;
    }
    &check_details($details);
    foreach my $detail (@$details) {
        $detail = &do_rh($detail, $defined_ops);
        # $detail =~ /(($symbol_p)\s*(=)\s*($symbol_p))/;
        &err_exit("wrong syntax in detail '$detail'")
            unless ($detail =~ /^\s*($symbol_p)\s*(=)\s*(.+)\s*$/);
        # say $3;
        my ($r_type, $r_code, $r_len) = &expand_op_str($3, $defined_ops);
        my $replace_code = &gen_assign($1, $r_type, $r_code, $r_len, $auto_vars, $defined_ops);
        substr($detail, 0, length($&)) = $replace_code;
        push @blocks, $detail;
    }
    push @blocks, "return new_ops;";
    join "\n", @blocks;
}

sub gen_assign {
    my $lhs = shift;
    my $rhs_type = shift;
    my $rhs_code = shift;
    my $rhs_len = shift;
    my $auto_vars = shift;
    my $defined_ops = shift;

    &err_exit("rhs_code cannot be undef") unless defined $rhs_code;
    unless ($lhs =~ /^(\w+)\.(ins|outs|params)\[((\w+(\$\@)?)|(\w+\$\^\w*)|(\w*\$\^\w+))\]$/) {
        &err_exit("wrong syntax in the lhs symbol of assignment '$lhs'");
    }
    &err_exit("undefined op '$1'") unless exists $defined_ops->{$1};

    my $opname = $1;
    my $optype = $defined_ops->{$opname};
    my $member = $2;
    my $arg_name = $3;
    my $code;
    if ($member eq "ins" or $member eq "outs") {
        $code = &gen_assign_tensor($opname, $optype, $member, $arg_name,
                                   $rhs_type, $rhs_code, $rhs_len, $auto_vars);
    } else {
        $code = &gen_assign_param($opname, $optype, $member, $arg_name,
                                  $rhs_type, $rhs_code, $rhs_len, $auto_vars);
    }
    $code;
}

sub gen_assign_tensor {
    my $opname = shift;
    my $optype = shift;
    my $member = shift;
    my $arg_name = shift;
    my $rhs_type = shift;
    my $rhs_code = shift;
    my $rhs_len = shift;
    my $auto_vars = shift;

    my $tensors = $member eq "ins" ? "tensors_in" : "tensors_out";
    &err_exit("rhs symbol must be a string (tensor name) for a tensor type lhs symbol")
        unless not defined $rhs_type or $rhs_type eq "char *";
    my $op_desc = &find_op_desc($optype);
    my $found = grep {$arg_name eq $_->{arg_name}} @{$op_desc->{$tensors}};
    my $code;
    if ($found) {
        $code = <<EOF;
{
    ln_tensor_list_entry *tle = ln_tensor_list_find_by_arg_name($opname->op_arg->$tensors,
                                                                "$arg_name");
    ln_free(tle->name);
    tle->name = ln_strdup($rhs_code);
}
EOF
    } elsif ($op_desc->{variable_length}) {
        if ($arg_name =~ /\$\@$/) {
            $arg_name =~ s/\$\@$//;
            push @$auto_vars, "int last_index;" unless grep /int last_index;/, @$auto_vars;
            $code = <<EOF;
{
    char arg_name[LN_MAX_NAME_LEN];
    last_index = ln_tensor_list_unique_arg_name($opname->op_arg->$tensors, arg_name, "$arg_name");
    $opname->op_arg->$tensors = ln_tensor_list_append($opname->op_arg->$tensors, arg_name, $rhs_code);
}
EOF
        } elsif ($arg_name =~ /(.*)\$\^(.*)/) {
            my $arg_name1 = $1;
            my $arg_name2 = $2;
            $code = <<EOF;
{
    char arg_name[LN_MAX_NAME_LEN];
    if (strlen("$arg_name1") + strlen("$arg_name2") + ln_digit_num(last_index) >= LN_MAX_NAME_LEN)
        ln_msg_inter_error("name '%s%d%s' length exceeds LN_MAX_NAME_LEN = %d",
                           "$arg_name1", last_index, "$arg_name2", LN_MAX_NAME_LEN);
    snprintf(arg_name, LN_MAX_NAME_LEN, "%s%d%s", "$arg_name1", last_index, "$arg_name2");
    $opname->op_arg->$tensors = ln_tensor_list_append($opname->op_arg->$tensors, arg_name, $rhs_code);
}
EOF
        } else {
            $code = <<EOF;
{
    $opname->op_arg->$tensors = ln_tensor_list_append($opname->op_arg->$tensors, "$arg_name", $rhs_code);
    ln_tensor_list_find_by_arg_name($opname->op_arg->$tensors, "$arg_name");
}
EOF
        }
    } else {
        err_exit("$opname($optype) doesn't have a '$arg_name' $tensors");
    }
    $code;
}

sub gen_assign_param {
    my $opname = shift;
    my $optype = shift;
    my $member = shift;
    my $arg_name = shift;
    my $rhs_type = shift;
    my $rhs_code = shift;
    my $rhs_len = shift;
    my $auto_vars = shift;

    &err_exit("unsupported rhs type '$rhs_type' for assignment")
        if defined $rhs_type and not exists $basic_types{$rhs_type} and
        not exists $array_types{$rhs_type};
    my $op_desc = &find_op_desc($optype);
    my $found = grep {$arg_name eq $_->{arg_name}} @{$op_desc->{params}};
    my $code;
    if ($found) {
        my $type = (&param_info($optype, "pe", $arg_name))[0];
        &err_exit("rhs type '$rhs_type' doesn't match lhs type '$type'")
            unless not defined $rhs_type or $type eq $rhs_type;
        &err_exit("lhs of an array type '$type' needs a length from rhs")
            if exists $array_types{$type} and not defined $rhs_len;
        &warn_msg("rhs type is not defined when assigning to type '$type': '$rhs_code'")
            unless defined $rhs_type;
        my $assign = &gen_copy_param("pe", $rhs_code, $type, $rhs_len);
        $assign = &indent_block($INDENT_OFFSET, $assign);
        $code = <<EOF;
{
    ln_param_entry *pe = ln_param_list_find($opname->op_arg->params, "$arg_name");
$assign
}
EOF
    } elsif ($op_desc->{variable_length}) {
        &err_exit("cannot generate variable-length params with undefined rhs type")
            unless defined $rhs_type;
        &err_exit("rhs of an array type '$rhs_type' needs a length")
            if exists $array_types{$rhs_type} and not defined $rhs_len;
        my $ptype = &type_to_ptype($rhs_type);
        my $assign = &gen_copy_param("pe", $rhs_code, $rhs_type, $rhs_len);
        $assign = &indent_block($INDENT_OFFSET, $assign);
        if ($arg_name =~ /\$\@$/) {
            $arg_name =~ s/\$\@$//;
            push @$auto_vars, "int last_index;" unless grep /int last_index;/, @$auto_vars;
            $code = <<EOF;
{
    char arg_name[LN_MAX_NAME_LEN];
    last_index = ln_param_list_unique_arg_name($opname->op_arg->params, arg_name, "$arg_name");
    $opname->op_arg->params = ln_param_list_append_empty($opname->op_arg->params, arg_name, $ptype);
    ln_param_entry *pe = ln_param_list_find($opname->op_arg->params, arg_name);
$assign
}
EOF
        } elsif ($arg_name =~ /(.*)\$\^(.*)/) {
            my $arg_name1 = $1;
            my $arg_name2 = $2;
            $code = <<EOF;
{
    char arg_name[LN_MAX_NAME_LEN];
    if (strlen("$arg_name1") + strlen("$arg_name2") + ln_digit_num(last_index) >= LN_MAX_NAME_LEN)
        ln_msg_inter_error("name '%s%d%s' length exceeds LN_MAX_NAME_LEN = %d",
                           "$arg_name1", last_index, "$arg_name2", LN_MAX_NAME_LEN);
    snprintf(arg_name, LN_MAX_NAME_LEN, "%s%d%s", "$arg_name1", last_index, "$arg_name2");
    $opname->op_arg->params = ln_param_list_append_empty($opname->op_arg->params, arg_name, $ptype);
    ln_param_entry *pe = ln_param_list_find($opname->op_arg->params, arg_name);
$assign
}
EOF
        } else {
            $code = <<EOF;
{
    $opname->op_arg->params = ln_param_list_append_empty($opname->op_arg->params, "$arg_name", $ptype);
    ln_param_entry *pe = ln_param_list_find($opname->op_arg->params, arg_name);
$assign
}
EOF
        }
    } else {
        &err_exit("$opname($optype) doesn't have a '$arg_name' params");
    }
    $code;
}

sub gen_copy_param {
    my $pe = shift;
    my $rhs = shift;
    my $type = shift;
    my $len = shift;

    my $code;
    my $member = &type_to_member($type);
    given ($type) {
        when ("char *") {
            $code = <<EOF;
{
    ln_free($pe->value_string);
    $pe->value_string = ln_strdup($rhs);
}
EOF
        }
        when ("char **") {
            $code = <<EOF;
{
    for (int i = 0; i < $pe->array_len; i++) {
        ln_free($pe->value_array_string[i]);
    }
    $pe->array_len = $len;
    ln_free($pe->value_array_string);
    $pe->value_array_string = ln_alloc(sizeof(char *)*($pe->array_len));
    for (int i = 0; i < $pe->array_len; i++) {
        $pe->value_array_string[i] = ln_strdup(${rhs}[i]);
    }
}
EOF
        }
        when (/^(int|float|double|ln_bool) \*$/) {
            my $ele_type = s/^(int|float|double|ln_bool) \*$/$1/r;
            $code = <<EOF;
{
    $pe->array_len = $len;
    ln_free($pe->$member);
    $pe->$member = ln_clone($rhs, sizeof($ele_type)*$pe->array_len);
}
EOF
        }
        when (/^(int|float|double|ln_bool)$/) {
            $code = <<EOF;
{
    $pe->$member = $rhs;
}
EOF
        }
        default {
            &err_exit("unknown type '$type', cannot generate assignment");
        }
    }
    $code;
}

sub check_details {
    my $details = shift;
    my %lhs_hash;
    foreach (@$details) {
        &err_exit("'details' can only contain assignments: '$_'")
            unless /(($symbol_p)\s*(=)\s*($symbol_p))/;
        my $lhs = $2;
        unless ($lhs =~ /^\w+\.(ins|outs|params)\[(\w+(\$\@)?)|(\w+\$\^\w*)|(\w*\$\^\w+)\]$/) {
            &err_exit("wrong syntax in the lhs symbol of assignment '$_'");
        }
        if (exists $lhs_hash{$lhs}) {
            if ($lhs =~ /\$\@/) {
                map {delete $lhs_hash{$_} if /\$\^/} keys %lhs_hash;
                next;
            }
            &err_exit("duplicated lhs symbol of assignment '$_'");
        }
        $lhs_hash{$lhs} = 1;
    }
}

sub gen_ep_funcs {
    my $ep_funcs = shift;

    push @$ep_funcs, "LN_HASH_INIT_ENTRY_NULL";
    &indent_lines($INDENT_OFFSET, $ep_funcs);
    my $entries = join "\n", @$ep_funcs;
    my $tpl = <<EOF;
static ln_hash_init_entry init_ep_funcs[] = {
$entries
};
static ln_hash *ep_funcs_hash = NULL;
EOF
}

sub gen_overall_funcs {
    my $name = shift;

    my $tpl = <<EOF;
void ln_expander_init_$name(void **context_p)
{
    ep_funcs_hash = ln_hash_create(ln_str_hash, ln_str_cmp, NULL, NULL);
    ln_hash_init(ep_funcs_hash, init_ep_funcs);
}

void ln_expander_cleanup_$name(void **context_p)
{
    ln_hash_free(ep_funcs_hash);
}

ln_list *ln_expander_$name(const ln_op *self, const ln_dfg *dfg, int *match)
{
    ln_expander_func  ep_func;
    ln_list          *new_ops;
    void             *value;

    if (!ln_hash_find_extended(ep_funcs_hash, self->op_arg->optype, NULL, &value))
        ln_msg_inter_error("unsupported optype \\"%s\\" for $name expander",
                           self->op_arg->optype);

    ep_func = value;
    new_ops = ep_func(self, dfg, match);

    return new_ops;
}
EOF
}

sub type_converse {
    my $type1 = shift;
    my $type2 = shift;

    if (not defined $type1 and not defined $type2) {
        return undef;
    }
    if (defined $type1 and not defined $type2) {
        return $type1;
    }
    if (not defined $type1 and defined $type2) {
        return $type2;
    }
    if ($type1 eq $type2) {
        return $type1;
    }
    if (not exists $basic_types{$type1} or not exists $basic_types{$type2}) {
        return 0;
    }
    if ($type1 eq "char *" or $type2 eq "char *") {
        return 0;
    }
    if ($type1 eq "char **" or $type2 eq "char **") {
        return 0;
    }
    if (exists $array_types{$type1} and exists $array_types{$type2}) {
        return "double *";
    }
    if (exists $basic_types{$type1} and exists $basic_types{$type2}) {
        return "double";
    }
    0;
}

sub add_to_arch_file {
    my $arch_file = shift;
    my $arch = shift;
    my $name = shift;

    my $declare = "extern ln_list *ln_expander_${name}(const ln_op *op, const ln_dfg *dfg, int *match);\n";
    my $item = "    ln_expander_${name},\n";
    my $init_func = "extern void ln_expander_init_${name}(void **context_p);\n";
    my $init_func_exec = "    ln_expander_init_${name}(context_p);\n";
    my $cleanup_func = "extern void ln_expander_cleanup_${name}(void **context_p);\n";
    my $cleanup_func_exec = "    ln_expander_cleanup_${name}(context_p);\n";

    copy($arch_file, "${arch_file}.bak")
        or die "Cannot backup file ${arch_file}: $!";
    open ARCH_FILE_BAK, '<', "${arch_file}.bak"
        or die "Cannot open ${arch_file}.bak: $!";
    open ARCH_FILE, '>', $arch_file
        or die "Cannot open ${arch_file}: $!";

    my $declared_done = 0;
    my $item_done = 0;
    my $init_func_done = 0;
    my $init_func_exec_done = 0;
    my $cleanup_func_done = 0;
    my $cleanup_func_exec_done = 0;
    while (<ARCH_FILE_BAK>) {
        $declared_done = 1 if $_ eq $declare;
        s|/\* end of declare $arch expanders \*/|$declare/* end of declare $arch expanders */|
            unless $declared_done;
        $item_done = 1 if $_ eq $item;
        s|/\* end of $arch expanders \*/|$item/* end of $arch expanders */|
            unless $item_done;
        $init_func_done = 1 if $_ eq $init_func;
        s|/\* end of declare $arch init funcs \*/|$init_func/* end of declare $arch init funcs */|
            unless $init_func_done;
        $init_func_exec_done = 1 if $_ eq $init_func_exec;
        s|/\* end of exec $arch init funcs \*/|$init_func_exec/* end of exec $arch init funcs */|
            unless $init_func_exec_done;
        $cleanup_func_done = 1 if $_ eq $cleanup_func;
        s|/\* end of declare $arch cleanup funcs \*/|$cleanup_func/* end of declare $arch cleanup funcs */|
            unless $cleanup_func_done;
        $cleanup_func_exec_done = 1 if $_ eq $cleanup_func_exec;
        s|/\* end of exec $arch cleanup funcs \*/|$cleanup_func_exec/* end of exec $arch cleanup funcs */|
            unless $cleanup_func_exec_done;
        print ARCH_FILE;
    }

    close ARCH_FILE;
    close ARCH_FILE_BAK;
}

sub do_rh {
    my $str = shift;
    my $defined_ops = shift;

    my $code;
    while ($str =~ /\$\{rh\s+($symbol_p)\s*\}/g) {
        $code = (&expand_op_str($1, $defined_ops))[1];
        my $pos_bak = pos($str);
        substr($str, pos($str)-length($&), length($&)) = $code;
        pos($str) = $pos_bak-length($&)+length($code);
    }
    $str;
}

sub expand_op_str {
    my $op_str = shift;
    my $defined_ops = shift;
    my ($directive, @directive_args);
    if ($op_str =~ /^\$\{.+\}$/) {
        &err_exit("wrong directive syntax: $op_str")
            unless ($op_str =~ /^\$\{(?<directive>[a-zA-Z0-9_-]+)(?:\((?<arg>.+)?\))?\s+(?<op>.+)\}/);
        $directive = $+{directive};
        @directive_args = split /,/, $+{arg} if exists $+{arg};
        $op_str = $+{op};
    }
    # while ($op_str =~ /($symbol_p)/g) {
    #     my $op_code = (&expand_op($1, $defined_ops))[1];
    #     substr($op_str, index($op_str, $1), length($1)) = $op_code;
    # }
    my @fs = split /\.|(?=\[)|(?==>)/, $op_str;
    my ($type, $code, $len);
    unless (exists $defined_ops->{$fs[0]}) {
        if ($op_str =~ /^\d+$/) {
            $type = "int";
        } elsif ($op_str =~ /^("(\\.|[^"\\])*")$/) {
            $type = "char *";
        } elsif ($op_str =~ /^([-+]?((\d*\.?\d+)|(\d+\.?\d*))([eE][-+]?\d+)?)$/) {
            $type = "double";
        } elsif (defined $directive and $directive eq "type") {
            &err_exit("directive 'type' needs one argument: $op_str")
                unless @directive_args == 1;
            $type = $directive_args[0];
        } else {
            &warn_msg("undefined symbol '$op_str' and its type");
        }
        return ($type, $op_str, $len);
    }
    my $optype = $defined_ops->{$fs[0]};

    my %member_path =
        (
         __self => ["ln_op *", "$fs[0]"],
         name => ["char *", "$fs[0]->op_arg->name"],
         optype => ["char *", "$fs[0]->op_arg->optype"],
         arch => ["char *", "$fs[0]->op_arg->arch"],
         tensor_table => ["char *", "$fs[0]->op_arg->tensor_table"],
         ins => {
                 __self => ["ln_list *", "$fs[0]->op_arg->tensors_in"],
                 len => ["int", "ln_list_length($fs[0]->op_arg->tensors_in)"],
                 "[]" => [\&expand_tensor, "in", $optype,
                          $fs[0], @fs[2..@fs-1]],
                },
         outs => {
                  __self => ["ln_list *", "$fs[0]->op_arg->tensors_out"],
                  len => ["int", "ln_list_length($fs[0]->op_arg->tensors_out)"],
                  "[]" => [\&expand_tensor, "out", $optype,
                           $fs[0], @fs[2..@fs-1]],
                 },
         params => {
                    __self => ["ln_list *", "$fs[0]->op_arg->params"],
                    len => ["int", "ln_list_length($fs[0]->op_arg->params)"],
                    "[]" => [\&expand_param, $optype,
                             $fs[0], @fs[2..@fs-1]],
                   },
        );

    ($type, $code, $len) = &parse_member_path(\%member_path, @fs);

    if (defined $directive and $directive eq "type") {
        &err_exit("directive 'type' needs one argument: $op_str")
            unless @directive_args == 1;
        $type = $directive_args[0];
    }

    ($type, $code, $len);
}

sub parse_member_path {
    my $path = shift;
    my @fs = @_;

    my ($type, $code, $len);
    my $ref = $path;
    my $index = -1;
    while (($index += 1) < @fs) {
        my $next_f = $fs[$index+1];
        if (ref $ref eq HASH) {
            if (ref $ref->{__self} eq ARRAY and ref $ref->{__self}->[0] eq CODE) {
                ($type, $code, $len) = &{$ref->{__self}->[0]}(@{$ref->{__self}}[1..@{$ref->{__self}}-1]);
            } else {
                ($type, $code, $len) = @{$ref->{__self}};
            }
            if ($next_f) {
                if ($next_f =~ /^\[.+\]$/) {
                    &err_unknown_field($index+1, @fs) unless exists $ref->{"[]"};
                    $ref = $ref->{"[]"};
                } elsif ($next_f =~ /^=>/) {
                    &err_unknown_field($index+1, @fs) unless exists $ref->{"=>"};
                    $ref = $ref->{"=>"};
                } elsif (exists $ref->{$next_f}) {
                    $ref = $ref->{$next_f};
                } else {
                    &err_unknown_field($index+1, @fs);
                }
            }
        } elsif (ref $ref eq ARRAY and ref $ref->[0] eq CODE) {
            ($type, $code, $len) = &{$ref->[0]}(@$ref[1..@$ref-1]);
        } else {
            ($type, $code, $len) = @$ref;
            &err_unknown_field($index+1, @fs) if ($next_f);
        }
    }

    ($type, $code, $len);
}

sub expand_tensor {
    my $in_or_out = shift;
    my $optype = shift;
    my $opname = shift;
    my @fs = @_;
    my $arg_name = $fs[0] =~ s/\[(.+)\]/$1/r;

    my $tensors = "tensors_$in_or_out";
    my $op_desc = &find_op_desc($optype);
    my $found = grep {$arg_name eq $_->{arg_name}} @{$op_desc->{$tensors}};

    my ($type, $code, $len);
    if ($found) {
        my $entry = "ln_tensor_list_find_entry($opname->op_arg->$tensors, $opname->op_arg->tensor_table, \"$arg_name\")";
        my %tensor_member =
            (
             __self => ["char *", "$entry->name"],
             "=>" => [\&topo_cond, $entry, @fs[1..@fs-1]],
             name => ["char *", "$entry->name"],
             owner => ["char *", "$entry->owner"],
             creater => ["char *", "$entry->creater"],
             tensor => ["tl_tensor *", "$entry->tensor"],
             offset => ["size_t", "$entry->offset"],
             isstatic => ["int", "$entry->isstatic"],
             mtype => ["ln_mem_type", "$entry->mtype"],
             dtype => ["tl_dtype", "$entry->tensor->dtype"],
             len => ["int", "$entry->tensor->len"],
             ndim => ["int", "$entry->tensor->ndim"],
             dims => {
                      __self => ["int *", "$entry->tensor->dims", "$entry->tensor->ndim"],
                      "[]" => [\&array_slice, "int", "$entry->tensor->dims", $fs[2]],
                     },
             data => ["void *", "$entry->tensor->data"],
             owner => ["struct tl_tensor *", "$entry->tensor->owner"],
             backend_data => ["void *", "$entry->tensor->backend_data"],
            );
        ($type, $code, $len) = &parse_member_path(\%tensor_member, @fs);
    } else {
        &util::err_exit("$opname($optype) doesn't have a '$arg_name' $tensors");
    }

    ($type, $code, $len);
}

sub topo_cond {
    my $entry = shift;
    my @params = @_;

    &err_exit("wrong syntax in a topo condition expr")
        unless $params[0] =~ /^=>\s*(\w+)?$/;
    my $optype = $1;

    unless (defined $optype) {
        my ($type, $code, $len);
        $type = "int";
        $code = <<EOF;
({
    ln_op *next_op;
    ln_tensor_entry *te;
    int ret;

    te = $entry;
    next_op = ln_dfg_next(dfg, self, te->name);
    if (!next_op) {
        ret = 1;
    } else {
        ret = 0;
    }
    ret;
})
EOF
        return ($type, $code, $len);
    }

    &err_exit("rhs in a topo condition expr should have 3 fields")
        unless @params == 3;
    &err_exit("wrong syntax in a topo condition expr")
        unless $params[1] =~ /^(ins|outs)$/;
    my $member = $1 eq "ins" ? "tensors_in" : "tensors_out";
    &err_exit("wrong syntax in a topo condition expr")
        unless $params[2] =~ /^\[(\w+)\]$/;
    my $arg_name = $1;

    my $op_desc = &find_op_desc($optype); # TODO: =>tensorrt.ins
    my $found = grep {$arg_name eq $_->{arg_name}} @{$op_desc->{$member}};
    &err_exit("unknown arg_name '$arg_name' of $op_desc->{optype} of the rhs in a topo condition expr")
        unless $found;

    my ($type, $code, $len);
    $type = "int";
    $code = <<EOF;
({
    ln_op *next_op;
    ln_tensor_entry *te;
    ln_tensor_list_entry *tle_next;
    int ret;

    te = $entry;
    next_op = ln_dfg_next(dfg, self, te->name);
    if (!next_op || !ln_streq(next_op->op_arg->optype, "$optype")) {
        ret = 0;
    } else {
        tle_next = ln_tensor_list_find_by_name(next_op->op_arg->$member, te->name);
        if (!tle_next)
            ret = 0;
        else if (!ln_streq(tle_next->arg_name, "$arg_name"))
            ret = 0;
        else
            ret = 1;
    }
    ret;
})
EOF

    ($type, $code, $len);
}

sub expand_param {
    my $optype = shift;
    my $opname = shift;
    my @fs = @_;
    my $arg_name = $fs[0] =~ s/\[(.+)\]/$1/r;

    my $op_desc = &find_op_desc($optype);
    my $found = grep {$arg_name eq $_->{arg_name}} @{$op_desc->{params}};

    my ($type, $code, $len);
    if ($found) {
        my $entry = "ln_param_list_find($opname->op_arg->params, \"$arg_name\")";
        my %param_member =
            (
             __self => [\&param_info, $optype, $entry, $arg_name],
             type => ["ln_param_type", "$entry->type"],
             array_len => ["int", "$entry->array_len"],
             len => ["int", "$entry->array_len"],
             value_double => ["double", "$entry->value_double"],
             value_float => ["float", "$entry->value_float"],
             value_int => ["int", "$entry->value_int"],
             value_bool => ["ln_bool", "$entry->value_bool"],
             value_string => ["char *", "$entry->value_string"],
             value_array_string => {
                                    __self => ["char **", "$entry->value_array_string",
                                               "$entry->array_len"],
                                    "[]" => [\&array_slice, "char *",
                                             "$entry->value_array_string", $fs[2]],
                                   },
             value_array_double => {
                                    __self => ["double *", "$entry->value_array_double",
                                               "$entry->array_len"],
                                    "[]" => [\&array_slice, "double",
                                             "$entry->value_array_double", $fs[2]],
                                   },
             value_array_float => {
                                   __self => ["float *", "$entry->value_array_float",
                                              "$entry->array_len"],
                                   "[]" => [\&array_slice, "float",
                                            "$entry->value_array_float", $fs[2]],
                                  },
             value_array_int => {
                                 __self => ["int *", "$entry->value_array_int",
                                            "$entry->array_len"],
                                 "[]" => [\&array_slice, "int",
                                          "$entry->value_array_int", $fs[2]],
                                },
             value_array_bool => {
                                  __self => ["ln_bool *", "$entry->value_array_bool",
                                             "$entry->array_len"],
                                  "[]" => [\&array_slice, "ln_bool",
                                           "$entry->value_array_bool", $fs[2]],
                                 },
             double => ["double", "$entry->value_double"],
             float => ["float", "$entry->value_float"],
             int => ["int", "$entry->value_int"],
             bool => ["ln_bool", "$entry->value_bool"],
             string => ["char *", "$entry->value_string"],
             array_string => {
                              __self => ["char **", "$entry->value_array_string",
                                         "$entry->array_len"],
                              "[]" => [\&array_slice, "char *",
                                       "$entry->value_array_string", $fs[2]],
                             },
             array_double => {
                              __self => ["double *", "$entry->value_array_double",
                                         "$entry->array_len"],
                              "[]" => [\&array_slice, "double",
                                       "$entry->value_array_double", $fs[2]],
                             },
             array_float => {
                             __self => ["float *", "$entry->value_array_float",
                                        "$entry->array_len"],
                             "[]" => [\&array_slice, "float",
                                      "$entry->value_array_float", $fs[2]],
                            },
             array_int => {
                           __self => ["int *", "$entry->value_array_int",
                                      "$entry->array_len"],
                           "[]" => [\&array_slice, "int",
                                    "$entry->value_array_int", $fs[2]],
                          },
             array_bool => {
                            __self => ["ln_bool *", "$entry->value_array_bool",
                                       "$entry->array_len"],
                            "[]" => [\&array_slice, "ln_bool",
                                     "$entry->value_array_bool", $fs[2]],
                           },
             "[]" => [\&param_slice, $optype, $entry, $arg_name, $fs[1]],
            );
        ($type, $code, $len) = &parse_member_path(\%param_member, @fs);
    } else {
        &err_exit("$opname($optype) doesn't have a '$arg_name' param");
    }

    ($type, $code, $len);
}

sub param_info {
    my $optype = shift;
    my $entry = shift;
    my $arg_name = shift;
    my $op_desc = &find_op_desc($optype);
    my ($element_type, $member);
    my ($type, $code, $len);
    foreach my $arg_name_desc (@{$op_desc->{params}}) {
        next unless $arg_name eq $arg_name_desc->{arg_name};
        given ($arg_name_desc->{ptype}) {
            when ("LN_PARAM_NULL") {
                $type = "ln_param_type";
                $member = "type";
            }
            when ("LN_PARAM_STRING") {
                $type = "char *";
                $member = "value_string";
            }
            when ("LN_PARAM_NUMBER") {
                $type = "$arg_name_desc->{realtype}";
                $member = "value_$arg_name_desc->{realtype}";
            }
            when ("LN_PARAM_BOOL") {
                $type = "ln_bool";
                $member = "value_bool";
            }
            when ("LN_PARAM_ARRAY_STRING") {
                $type = "char **";
                $len = "$entry->array_len";
                $member = "value_array_string";
            }
            when ("LN_PARAM_ARRAY_NUMBER") {
                $type = "$arg_name_desc->{realtype} *";
                $len = "$entry->array_len";
                $member = "value_array_$arg_name_desc->{realtype}";
            }
            when ("LN_PARAM_ARRAY_BOOL") {
                $type = "ln_bool *";
                $len = "$entry->array_len";
                $member = "value_array_bool";
            }
            default {
                &util::err_exit("unsupported ptype '$_' for optype '$optype''s param '$arg_name'");
            }
        }
    }
    $code = "$entry->$member";
    ($type, $code, $len);
}

sub param_slice {
    my $optype = shift;
    my $entry = shift;
    my $arg_name = shift;
    my $index_str = shift;
    my $op_desc = &find_op_desc($optype);
    my ($element_type, $member);
    my ($type, $code, $len);
    foreach my $arg_name_desc (@{$op_desc->{params}}) {
        next unless $arg_name eq $arg_name_desc->{arg_name};
        given ($arg_name_desc->{ptype}) {
            when ("LN_PARAM_ARRAY_STRING") {
                $type = "char **";
                $element_type = "char *";
                $member = "value_array_string";
            }
            when ("LN_PARAM_ARRAY_NUMBER") {
                $type = "$arg_name_desc->{realtype} *";
                $element_type = "$arg_name_desc->{realtype}";
                $member = "value_array_$arg_name_desc->{realtype}";
            }
            when ("LN_PARAM_ARRAY_BOOL") {
                $type = "ln_bool *";
                $element_type = "ln_bool";
                $member = "value_array_bool";
            }
            default {
                &util::err_exit("unsupported '[]' operator for optype '$optype''s param '$arg_name'");
            }
        }
    }
    $code = "$entry->$member";
    ($type, $code, $len) = &array_slice($element_type, $code, $index_str);
}

sub type_to_member {
    my $type = shift;

    my %table = (int => "value_int", double => "value_double", float => "value_float",
                 ln_bool => "value_bool", "char *" => "value_string",
                 "char **" => "value_array_string", "double *" => "value_array_double",
                 "float *" => "value_array_float", "int *" => "value_array_int",
                 "ln_bool *" => "value_array_bool");
    &err_exit("unknow type '$type'") unless exists $table{$type};
    $table{$type};
}

sub type_to_ptype {
    my $type = shift;

    my %table = (int => "LN_PARAM_NUMBER", double => "LN_PARAM_NUMBER",
                 float => "LN_PARAM_NUMBER", ln_bool => "LN_PARAM_BOOL",
                 "char *" => "LN_PARAM_STRING",
                 "char **" => "LN_PARAM_ARRAY_STRING",
                 "double *" => "LN_PARAM_ARRAY_NUMBER",
                 "float *" => "LN_PARAM_ARRAY_NUMBER",
                 "int *" => "LN_PARAM_ARRAY_NUMBER",
                 "ln_bool *" => "LN_PARAM_ARRAY_BOOL");
    &err_exit("unknow type '$type'") unless exists $table{$type};
    $table{$type};
}

sub array_slice {
    my $element_type = shift;
    my $initial_code = shift;
    my $index_str = shift;
    $index_str =~ s/\[(.+)\]/$1/;
    my @indexes = split /\s*,\s*/, $index_str;

    my ($type, $code, $len);
    $len = @indexes;
    if (@indexes == 1) {
        ($type, $code) = ($element_type, "${initial_code}[$indexes[0]]");
    } else {
        $type = "$element_type *";
        my @array;
        foreach (@indexes) {
            push @array, "${initial_code}[$_]";
        }
        my $array_str = join ', ', @array;
        $code = "(${element_type}[]){$array_str}";
    }
    ($type, $code, $len);
}

sub find_op_desc {
    my $optype = shift;
    my $op = $global_ops{$optype};
    unless ($op) {
        my $opdir = abs_path(dirname(__FILE__))."/../protos/op";
        my @possible_files = &possible_op_files($optype);
        foreach (@possible_files) {
            my $file = "$opdir/$_";
            next unless -e $file;
            &read_ops_json($file, \%global_ops);
            $op = $global_ops{$optype} if exists $global_ops{$optype};
        }
        unless ($op) {
            &util::err_exit("Cannot find the description JSON for optype '$optype'");
        }
    }
    $op;
}

sub possible_op_files {
    my $optype = shift;
    my @names = ();
    my @words = split '_', $optype;
    if (@words == 1) {
        push @names, $optype.'.json';
    } else {
        push @names, (join '_', @words[0..$#words-1]).'.json';
        push @names, $optype.'.json';
    }
    @names;
}

sub read_json_text {
    my $json_text = shift;
    $json_text = easyjson::easy_to_json($json_text);
    my $json_obj = JSON->new->relaxed();
    my $json = $json_obj->decode($json_text);
}

sub read_json {
    my $file = shift;
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $text = join '', <$fh>;
    close $fh;
    &read_json_text($text);
}

sub read_ops_json {
    my $file = shift;
    my $hash = shift;
    my $json = &read_json($file);
    if (exists $json->{ops}) {
        foreach my $op (@{$json->{ops}}) {
            $hash->{$op->{optype}} = $op;
        }
    } elsif (exists $json->{optype}) {
        $hash->{$json->{optype}} = $json;
    } else {
        &util::err_exit("JSON file $file doesn't contain an 'ops' or 'optype' field");
    }
}

sub err_unknown_field {
    my $index = shift;
    my @fields = @_;
    my $prefix = join '.', @fields[0..$index-1];
    my $subfix = $fields[$index];
    &util::err_exit("$prefix doesn't have a '$subfix' field");
}

sub err_unknown_last_field {
    my @fields = @_;
    &err_unknown_field($#fields, @fields);
}

1;
