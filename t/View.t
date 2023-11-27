#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 12;

use_ok('View');
can_ok( 'View', 'colored_bold' );
can_ok( 'View', 'colored_faint' );
can_ok( 'View', 'colored_by_index' );
{
    my $message = "SecretMessage";
    my $result  = colored_by_index( $message, 0 );

    isnt( $result, $message, "colored_by_index should add something" );
    like( $result, qr/$message/,
        "colored_by_index result should contain message" );
    isnt(
        $result,
        colored_by_index( $message, 1 ),
        "colored_by_index result should differ by index"
    );
}
can_ok( 'View', 'dump_struct' );
can_ok( 'View', 'pretty_path' );
can_ok( 'View', 'print_crud' );
can_ok( 'View', 'print_with_icon' );
can_ok( 'View', 'trace' );
