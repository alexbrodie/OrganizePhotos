use strict;
use warnings;
use Test::More tests => 7;

use_ok('Test::Pod::Coverage 1.04');

use_ok('Orph::Depot::Record');
pod_coverage_ok('Orph::Depot::Record');

can_ok( 'Orph::Depot::Record', 'new' );
{
    my $record = Orph::Depot::Record->new(
        {
            filename => 'foo.ext',
            mtime    => 123,
            size     => 42
        }
    );

    is( $record->filename, 'foo.ext', 'filename' );
    is( $record->mtime,    123,       'mtime' );
    is( $record->size,     42,        'size' );
}
