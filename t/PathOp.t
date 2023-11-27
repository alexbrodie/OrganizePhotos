#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 11;

use_ok('PathOp');
can_ok( 'PathOp', 'change_filename' );
{
    is( change_filename( '/foo/bar/fname.ext', 'replacement.new' ),
        '/foo/bar/replacement.new' );

    #is( change_filename('C:\\foo\\bar\\fname.ext', 'replacement.new'),
    #    'C:\\foo\\bar\\replacement.new');

    is( change_filename( '/foo/bar/fname.ext', undef ), '/foo/bar' );

    #is( change_filename('C:\\foo\\bar\\fname.ext', undef),
    #    'C:\\foo\\bar');
}
can_ok( 'PathOp', 'combine_dir' );
can_ok( 'PathOp', 'combine_ext' );
can_ok( 'PathOp', 'combine_path' );
can_ok( 'PathOp', 'parent_path' );
can_ok( 'PathOp', 'split_dir' );
can_ok( 'PathOp', 'split_ext' );
can_ok( 'PathOp', 'split_path' );
