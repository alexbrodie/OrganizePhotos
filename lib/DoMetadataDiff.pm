#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoMetadataDiff;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    do_metadata_diff
);

# Local uses
use MetaData qw(read_metadata);
use View qw(colored_bold colored_by_index colored_faint);

# Library uses
use List::Util qw(any max);

# Execute metadata-diff verb
# skip_missing: if truthy, treat missing files as having no metadata rather than failing
# exclude_sidecars: do not include sidecar metadata
sub do_metadata_diff {
    my ($skip_missing, $exclude_sidecars, @paths) = @_;
    # Get metadata for all files
    my @items = map { (!$skip_missing || -e) ? read_metadata($_, $exclude_sidecars) : {} } @paths;
    my @tags_to_skip = qw(CurrentIPTCDigest DocumentID DustRemovalData 
        FileInodeChangeDate FileName HistoryInstanceID IPTCDigest InstanceID
        OriginalDocumentID PreviewImage RawFileName ThumbnailImage);
    # Collect all the tags which whose values aren't all equal
    my %tag_set = ();
    for (my $i = 0; $i < @items; $i++) {
        while (my ($tag, $value) = each %{$items[$i]}) {
            unless (any { $_ eq $tag } @tags_to_skip) {
                for (my $j = 0; $j < @items; $j++) {
                    if ($i != $j and
                        (!exists $items[$j]->{$tag} or
                         $items[$j]->{$tag} ne $value)) {
                        $tag_set{$tag} = 1;
                        last;
                    }
                }
            }
        }
    }
    # Pretty print all the keys and associated values which differ
    my @tags_list = sort keys %tag_set;
    my $indent_length = 3 + max(0, map { length } @tags_list); 
    for my $tag (@tags_list) {
        for (my $i = 0; $i < @items; $i++) {
            my $message = $items[$i]->{$tag} || colored_faint('undef');
            if ($i == 0) {
                print colored_bold($tag), '.' x ($indent_length - length $tag);
            } else {
                print ' ' x $indent_length;
            }
            print colored_by_index($message, $i), "\n";
        }
    }
}

1;