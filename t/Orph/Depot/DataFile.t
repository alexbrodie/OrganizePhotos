use strict;
use warnings;
use Test::More tests => 7;

use_ok('FileOp');
use_ok('Orph::Depot::Record');
use_ok('Test::Pod::Coverage 1.04');

use_ok('Orph::Depot::DataFile');
pod_coverage_ok('Orph::Depot::DataFile');

can_ok( 'Orph::Depot::DataFile', 'new' );
{
    my $original_record_set =
        { map { lc $_ => Orph::Depot::Record->new( { filename => $_ } ) }
            qw(foo.ext bar.xyz) };

    my $path = "t/temp/.orphdat";
    ensure_parent_dir($path);

    # Write out file
    {
        my $file = Orph::Depot::DataFile->new($path);
        $file->access_rw();
        $file->write_records($original_record_set);
    }

    # Read back in and cleanup
    my $persisted_record_set;
    {
        my $file = Orph::Depot::DataFile->new($path);
        $file->access('<');
        $persisted_record_set = $file->read_records();
        $file->erase();
    }

    is_deeply( $original_record_set, $persisted_record_set,
        "record set round trip" )
}
