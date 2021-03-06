#! /usr/bin/env perl

use warnings;
use strict;
use Cwd 'abs_path';
use File::Basename;
use lib abs_path(dirname(__FILE__));
use util;

my $usage = <<EOF;
Usage: $0 SRC DST -d DEFINE(s) -i INCLUDES
Generate C defines and includes after /* start of config */ from SRC to DST.

Example:
	tools/addconfig.pl src/config.h.in build/include/config.h \
    -d USE_XXX USE_YYY -i a.h b.h

	This example will generate
	/* start of config */
	#define USE_XXX
	#define USE_YYY

    #include "a.h"
    #include "b.h"
EOF

util::exit_msg($usage) if $ARGV[0] eq "-h" or $ARGV[0] eq "--help";
util::err_exit($usage) if @ARGV < 4;

my $src = shift @ARGV;
my $dst = shift @ARGV;
util::err_exit($usage) if shift @ARGV ne "-d";

my @defines;
my $define;
while (($define = shift @ARGV) ne "-i") {
    push @defines, $define;
}

my @includes = @ARGV;

my @configs;
foreach (@defines) {
    push @configs, "#ifndef ".(split)[0];
    push @configs, "#define $_";
    push @configs, "#endif"
}
push @configs, "";
foreach (@includes) {
    push @configs, "#include \"$_\"";
}
my $config_str = join "\n", @configs;

open DST, '>', $dst or die "Cannot open $dst: $!";
open SRC, '<', $src or die "Cannot open $src: $!";
while (<SRC>) {
    s|/\* start of config \*/|/\* start of config \*/\n$config_str|;
    print DST;
}
close SRC;
close DST;
