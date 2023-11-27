#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;

use_ok('TraverseFiles');
can_ok( 'TraverseFiles', 'default_is_dir_wanted' );
{
    ok( default_is_dir_wanted( 'Photos',      '.', 'Photos' ) );
    ok( !default_is_dir_wanted( '.OrPhTrash', '.', '.OrPhTrash' ) );
}
can_ok( 'TraverseFiles', 'default_is_file_wanted' );
{
    ok( default_is_file_wanted( 'IMG_1234.jpg', '.', 'IMG_1234.jpg' ) );
    ok( !default_is_file_wanted( '.OrPhDat',    '.', '.OrPhDat' ) );
}
can_ok( 'TraverseFiles', 'traverse_files' );
