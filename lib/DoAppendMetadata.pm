#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoAppendMetadata;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doAppendMetadata
);

# Local uses
use MetaData qw(extract_info);
use View;

# EXPERIMENTAL
# Execute append-metadata verb
sub doAppendMetadata {
    my ( $target, @sources ) = @_;

    my @properties =
        qw(XPKeywords Rating Subject HierarchicalSubject LastKeywordXMP Keywords);

    # Extract current metadata in target
    my $etTarget   = extract_info($target);
    my $infoTarget = $etTarget->GetInfo(@properties);

    trace( $VERBOSITY_MAX, "$target: ", Data::Dumper::Dumper($infoTarget) );

    my $rating    = $infoTarget->{Rating};
    my $oldRating = $rating;

    my %keywordTypes = ();
    for (qw(XPKeywords Subject HierarchicalSubject LastKeywordXMP Keywords)) {
        my $old = $infoTarget->{$_};
        $keywordTypes{$_} = {
            OLD => $old,
            NEW => { map { $_ => 1 } split /\s*,\s*/, ( $old || '' ) }
        };
    }

    for my $source (@sources) {

        # Extract metadata in source to merge in
        my $etSource   = extract_info($source);
        my $infoSource = $etSource->GetInfo(@properties);

        trace( $VERBOSITY_MAX, "$source: ", Data::Dumper::Dumper($infoSource) );

        # Add rating if we don't already have one
        unless ( defined $rating ) {
            $rating = $infoSource->{Rating};
        }

        # For each field, loop over each component of the source's value
        # and add it to the set of new values
        while ( my ( $name, $value ) = each %keywordTypes ) {
            for ( split /\s*,\s*/, $infoSource->{$name} ) {
                $value->{NEW}->{$_} = 1;
            }
        }
    }

    my $dirty = 0;

    # Update rating if it's changed
    if (   ( defined $rating )
        && ( ( !defined $oldRating ) || ( $rating ne $oldRating ) ) )
    {
        print "Rating: ",
            defined $oldRating ? $oldRating : "(null)",
            " -> $rating\n";
        $etTarget->SetNewValue( 'Rating', $rating )
            or die "Couldn't set Rating";
        $dirty = 1;
    }

    while ( my ( $name, $value ) = each %keywordTypes ) {
        my $old = $value->{OLD};
        my $new = join ', ', sort keys %{ $value->{NEW} };
        if ( ( $old || '' ) ne $new ) {
            print "$name: ",
                defined $old ? "\"$old\"" : "(null)",
                " -> \"$new\"\n";
            $etTarget->SetNewValue( $name, $new )
                or die "Couldn't set $name";
            $dirty = 1;
        }
    }

    # Write file if metadata is dirty
    if ($dirty) {

        # Compute backup path
        my $backup = "${target}_bak";
        for ( my $i = 2; -s $backup; $i++ ) {
            $backup =~ s/_bak\d*$/_bak$i/;
        }

        # Make backup
        File::Copy::copy( $target, $backup )
            or die "Couldn't copy $target to $backup: $!";

        # Update metadata in target file
        my $write = $etTarget->WriteInfo($target);
        if ( $write == 1 ) {

            # updated
            print "Updated $target\nOriginal backed up to $backup\n";
        }
        elsif ( $write == 2 ) {

            # noop
            print "$target was already up to date\n";
        }
        else {
            # failure
            die "Couldn't WriteInfo for $target";
        }
    }
}

1;
