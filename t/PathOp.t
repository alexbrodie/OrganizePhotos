#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

# If this fails to locate, don't forget prove's -l flag
use_ok('PathOp');

can_ok('PathOp', 'change_filename');

is( change_filename('/foo/bar/fname.ext', 'replacement.new'),
    '/foo/bar/replacement.new');

#is( change_filename('C:\\foo\\bar\\fname.ext', 'replacement.new'),
#    'C:\\foo\\bar\\replacement.new');

is( change_filename('/foo/bar/fname.ext', undef),
    '/foo/bar');

#is( change_filename('C:\\foo\\bar\\fname.ext', undef),
#    'C:\\foo\\bar');

