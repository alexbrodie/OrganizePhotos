#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 5;

use_ok('Orph::Depot::RecordKey');
can_ok( 'Orph::Depot::RecordKey', 'new' );
{
    my $key = Orph::Depot::RecordKey->new('/Path/To/Some/Image.JPG');
    is( $key->subject_path, '/Path/To/Some/Image.JPG' );
    is( $key->depot_path,   '/Path/To/Some/.orphdat' );
    is( $key->record_key,   'image.jpg' );
}
