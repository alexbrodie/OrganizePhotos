#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 11;

use_ok('FileTypes');
can_ok( 'FileTypes', 'get_file_type_info' );
{
    is( get_file_type_info( 'jpg',  'EXTORDER' ), undef );
    is( get_file_type_info( '.CRW', 'EXTORDER' ), -1 );
}
can_ok( 'FileTypes', 'get_mime_type' );
{
    is( get_mime_type('foo.jpg'), 'image/jpeg' );
    is( get_mime_type('Bar.Mov'), 'video/quicktime' );
}
can_ok( 'FileTypes', 'get_sidecar_paths' );
can_ok( 'FileTypes', 'get_trash_path' );
can_ok( 'FileTypes', 'compare_path_with_ext_order' );
can_ok( 'FileTypes', 'is_reserved_system_filename' );
