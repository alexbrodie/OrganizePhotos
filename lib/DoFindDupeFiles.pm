#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoFindDupeFiles;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doFindDupeFiles
);

# Local uses
#use ContentHash;
use DoAppendMetadata qw(doAppendMetadata);
use DoMetadataDiff   qw(do_metadata_diff);
use FileOp           qw(trash_path_and_sidecars);
use FileTypes        qw(get_sidecar_paths compare_path_with_ext_order);
use MetaData         qw(get_date_taken);
use OrPhDat          qw(resolve_orphdat find_orphdat trash_orphdat);
use PathOp           qw(combine_ext split_dir split_ext split_path);
use TraverseFiles
    qw(traverse_files default_is_dir_wanted default_is_file_wanted);
use View;

# Library uses
use List::Util           qw(all max);
use Number::Bytes::Human qw(format_bytes);
use POSIX                qw(strftime);
use Readonly;

my $autoTrashDuplicatesFrom = [ '/Volumes/CFexpress/', '/Volumes/MicroSD/', ];

Readonly::Scalar my $MATCH_UNKNOWN => 0;
Readonly::Scalar my $MATCH_NONE    => 1;
Readonly::Scalar my $MATCH_FULL    => 2;
Readonly::Scalar my $MATCH_CONTENT => 3;

# Execute find-dupe-files verb
sub doFindDupeFiles {
    my ( $byName, $autoDiff, $defaultLastAction, @globPatterns ) = @_;
    my $dupeGroups  = buildFindDupeFilesDupeGroups( $byName, @globPatterns );
    my $lastCommand = '';
DUPEGROUP:
    for (
        my $dupeGroupsIdx = 0;
        $dupeGroupsIdx < @$dupeGroups;
        $dupeGroupsIdx++
        )
    {
        print "\033[K\n";
        while (1) {
            my $group = $dupeGroups->[$dupeGroupsIdx];
            populateFindDupeFilesDupeGroup($group);

            # Auto command is what happens without any user input
            my $command = generateFindDupeFilesAutoAction($group);

            # Default command is what happens if you hit enter with an empty string
            # (ignored if there's an auto command).
            my $defaultCommand = $defaultLastAction ? $lastCommand : undef;

            # Main heading for group
            my $prompt = "Resolving duplicate group @{[$dupeGroupsIdx + 1]} "
                . "of @{[scalar @$dupeGroups]}\n";
            $prompt .= buildFindDupeFilesPrompt( $group, $defaultCommand );
            do_metadata_diff( 1, 0, map { $_->{fullPath} } @$group )
                if $autoDiff;

            # Prompt for command(s)
            if ($command) {
                print $prompt, $command, "\n";
            }
            else {
                until ($command) {
                    print $prompt, "\a";
                    chomp( $command = <STDIN> );
                    if ($command) {

                        # If the user provided something, save that for next
                        # conflict's default (the next DUPEGROUP)
                        $lastCommand = $command;
                    }
                    elsif ($defaultCommand) {
                        $command = $defaultCommand;
                    }
                }
            }
            my $usage = <<"EOM";
?   Help: shows this help message
c   Continue: go to the next group
d   Diff: perform metadata diff of this group
o#  Open Number: open the specified item
q   Quit: exit the application
t#  Trash Number: move the specified item to $FileTypes::TRASH_DIR_NAME
EOM

            # Process the command(s)
            my $itemCount = @$group;
            for ( split /;/, $command ) {
                if ( $_ eq '?' ) {
                    print $usage;
                }
                elsif ( $_ eq 'c' ) {
                    next DUPEGROUP;
                }
                elsif ( $_ eq 'd' ) {
                    do_metadata_diff( 1, 0, map { $_->{fullPath} } @$group );
                }
                elsif (/^f(\d+)$/) {
                    if ( $1 > $#$group ) {
                        warn "$1 is out of range [0, $#$group]";
                    }
                    elsif ( !defined $group->[$1] ) {
                        warn "$1 has already been trashed";
                    }
                    elsif ( $^O eq 'MSWin32' ) {
                        system(
                            "explorer.exe /select,\"$group->[$1]->{fullPath}\""
                        );
                    }
                    elsif ( $^O eq 'darwin' ) {
                        system("open -R \"$group->[$1]->{fullPath}\"");
                    }
                    else {
                        warn "Don't know how to open a folder on $^O\n";
                    }
                }
                elsif (/^m(\d+(?:,\d+)+)$/) {
                    doAppendMetadata( map { $group->[$_]->{fullPath} }
                            split ',', $1 );
                }
                elsif (/^o(\d+)$/) {
                    if ( $1 > $#$group ) {
                        warn "$1 is out of range [0, $#$group]";
                    }
                    elsif ( !defined $group->[$1] ) {
                        warn "$1 has already been trashed";
                    }
                    else {
                        system("open \"$group->[$1]->{fullPath}\"");
                    }
                }
                elsif ( $_ eq 'q' ) {
                    exit 0;
                }
                elsif (/^t(\d+)$/) {
                    if ( $1 > $#$group ) {
                        warn "$1 is out of range [0, $#$group]";
                    }
                    elsif ( !defined $group->[$1] ) {
                        warn "$1 has already been trashed";
                    }
                    else {
                        if ( $group->[$1]->{exists} ) {
                            trash_path_and_sidecars( $group->[$1]->{fullPath} );
                        }
                        else {
                            trash_orphdat( $group->[$1]->{fullPath} );
                        }
                        $group->[$1] = undef;
                        $itemCount--;

                        # TODO: rather than maintaining itemCount, maybe just
                        # dynmically calc: (scalar grep { defined $_ } @$group)
                        ( scalar grep { defined $_ } @$group ) == $itemCount
                            or die "Programmer Error: bad itemCount calc";
                        next DUPEGROUP if $itemCount < 2;
                    }
                }
                else {
                    warn "Unrecognized command: '$_'";
                    print $usage;
                }
            }
        }    # while (1)
    }    # DUPEGROUP
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Builds a list of dupe groups where each group is a list of hashes that
# initially only contain the fullPath. Lists are sorted descending by
# importance. So the return will be of the form:
#   [
#       [
#           { fullPath => '/first/group/first.file' },
#           { fullPath => '/first/group/second.file' }
#       ],
#       [
#           { fullPath => '/second/group/first.file' },
#           { fullPath => '/second/group/second.file' }
#       ]
#   ]
# In addition to fullPath, a cachedMd5Info property may be added if
# available.
sub buildFindDupeFilesDupeGroups {
    my ( $byName, @globPatterns ) = @_;

    # Create the initial groups in various ways with key that is opaque
    # and ignored from the outside
    my %keyToFullPathList = ();
    if ($byName) {

        # Hash key based on file/dir name
        traverse_files(
            \&default_is_dir_wanted,     # isDirWanted
            \&default_is_file_wanted,    # isFileWanted
            sub {                        # callback
                my ( $fullPath, $rootFullPath ) = @_;
                if ( -f $fullPath ) {
                    my $key = computeFindDupeFilesHashKeyByName($fullPath);
                    push @{ $keyToFullPathList{$key} },
                        { fullPath => $fullPath };
                }
            },
            @globPatterns
        );
    }
    else {
        # Hash key is MD5
        find_orphdat(
            \&default_is_dir_wanted,     # isDirWanted
            \&default_is_file_wanted,    # isFileWanted
            sub {                        # callback
                my ( $fullPath, $md5Info ) = @_;
                push @{ $keyToFullPathList{ $md5Info->{md5} } },
                    { fullPath => $fullPath, cachedMd5Info => $md5Info };
            },
            @globPatterns
        );
    }
    trace( $VERBOSITY_MAX,
        "Found @{[scalar keys %keyToFullPathList]} initial groups" );

    # Go through each element in the %keyToFullPathList map, and we'll
    # want the ones with multiple things in the array of paths. If
    # there  are multiple paths for an element, sort the paths array
    # by decreasing importance (our best guess), and add it to the
    # @dupes collection for further processing.
    my @dupes     = ();
    my $fileCount = 0;
    while ( my ( $key, $fullPathList ) = each %keyToFullPathList ) {
        $fileCount += @$fullPathList;
        if ( @$fullPathList > 1 ) {
            my @group = sort {
                compare_path_with_ext_order( $a->{fullPath}, $b->{fullPath}, 0 )
            } @$fullPathList;
            push @dupes, \@group;
        }
    }

    # The 2nd level is properly sorted, now let's sort the groups
    # themselves - this will be the order in which the groups
    # are processed, so we want it extorder based as well.
    @dupes = sort {
        compare_path_with_ext_order( $a->[0]->{fullPath},
            $b->[0]->{fullPath}, 1 )
    } @dupes;
    print_crud( $VERBOSITY_LOW, $CRUD_READ,
        "Found $fileCount files and @{[scalar @dupes]} groups of duplicate files"
    );
    return \@dupes;
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Adds the following properties to a group created by
# buildFindDupeFilesDupeGroups:
#   exists: cached result of -e check
#   md5Info: Md5Info data
#   dateTaken: a DateTime value obtained via get_date_taken
#   matches: array of $MATCH_* values of comparison with other group elements
sub populateFindDupeFilesDupeGroup {
    my ($group) = @_;
    my $fast = 0;      # avoid slow operations, potentially with less precision?
    @$group = grep { defined $_ } @$group;
    for my $elt (@$group) {
        $elt->{exists} = -e $elt->{fullPath};
        if ( $fast || !$elt->{exists} ) {
            delete $elt->{md5Info};
            delete $elt->{dateTaken};
        }
        else {
            $elt->{md5Info} = resolve_orphdat( $elt->{fullPath}, 0, 0,
                exists $elt->{md5Info}
                ? $elt->{md5Info}
                : $elt->{cachedMd5Info} );
            $elt->{dateTaken} = get_date_taken( $elt->{fullPath} );
        }
        $elt->{sidecars} =
            $elt->{exists} ? [ get_sidecar_paths( $elt->{fullPath} ) ] : [];
    }
    for ( my $i = 0; $i < @$group; $i++ ) {
        $group->[$i]->{matches}->[$i] = $MATCH_FULL;
        my ( $iFullMd5, $iContentMd5 ) =
            @{ $group->[$i]->{md5Info} }{qw(full_md5 md5)};
        for ( my $j = $i + 1; $j < @$group; $j++ ) {
            my ( $jFullMd5, $jContentMd5 ) =
                @{ $group->[$j]->{md5Info} }{qw(full_md5 md5)};
            my $matchType = $MATCH_UNKNOWN;
            if ( $iFullMd5 and $jFullMd5 ) {
                if ( $iFullMd5 eq $jFullMd5 ) {
                    $matchType = $MATCH_FULL;
                }
                else {
                    $matchType = $MATCH_NONE;
                }
            }
            if ( $matchType != $MATCH_FULL ) {
                if ( $iContentMd5 and $jContentMd5 ) {
                    if ( $iContentMd5 eq $jContentMd5 ) {
                        $matchType = $MATCH_CONTENT;
                    }
                    else {
                        $matchType = $MATCH_NONE;
                    }
                }
            }
            $group->[$i]->{matches}->[$j] = $matchType;
            $group->[$j]->{matches}->[$i] = $matchType;
        }
    }
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
sub computeFindDupeFilesHashKeyByName {
    my ($fullPath) = @_;
    my ( $vol, $dir, $filename ) = split_path($fullPath);
    my ( $basename, $ext ) = split_ext($filename);

    # 1. Start with extension
    my $key = lc $ext . ';';

    # 2. Add basename
    my $nameRegex = qr/^
        (
            # things like DCF_1234
            [a-zA-Z\d_]{4} \d{4} |
            # things like 2009-08-11 12_31_45
            \d{4} [-_] \d{2} [-_] \d{2} [-_\s] 
            \d{2} [-_] \d{2} [-_] \d{2}
        ) \b /x;
    if ( $basename =~ /$nameRegex/ ) {

        # This is an understood filename format, so just take
        # the root so that we can ignore things like "Copy (2)"
        $key .= lc $1 . ';';
    }
    else {
        # Unknown file format, just use all of basename? It's not
        # nothing, but will only work with exact filename matches
        warn
            "Unknown filename format for '$basename' in '@{[pretty_path($fullPath)]}'";
        $key .= lc $basename . ';';
    }

    # 3. Directory info
    my $nameKeyIncludesDir = 1;
    if ($nameKeyIncludesDir) {

        # parent dir should be similar (based on date format)
        my $dirRegex = qr/^
            # yyyy-mm-dd or yy-mm-dd or yyyymmdd or yymmdd
            (?:19|20)?(\d{2}) [-_]? (\d{2}) [-_]? (\d{2}) \b
            /x;
        my $dirKey = '';
        for ( reverse File::Spec->splitdir($dir) ) {
            if (/$dirRegex/) {
                $dirKey = "$1$2$3;";
                last;
            }
        }
        if ($dirKey) {
            $key .= $dirKey;
        }
        else {
            warn "Unknown directory format in '@{[pretty_path($fullPath)]}'";
        }
    }
    return $key;
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Computes zero or more commands that should be auto executed for the
# provided fully populated group.
sub generateFindDupeFilesAutoAction {
    my ($group) = @_;
    my @autoCommands = ();

    # Figure out what's trashable, starting by excluding missing files
    my @remainingIdx = grep { $group->[$_]->{exists} } ( 0 .. $#$group );
    filterIndicies(
        $group,
        \@remainingIdx,
        sub {
            # Don't auto trash things with sidecars
            return 1 if @{ $_->{sidecars} };
            $_->{fullPath} !~ /[\/\\]ToImport[\/\\]/;
        }
    );
    if ( @remainingIdx > 1
        && all { $_ == $MATCH_FULL }
        @{ $group->[ $remainingIdx[0] ]->{matches} }[@remainingIdx] )
    {
        # We have several things left that are all exact matches with no sidecars
        filterIndicies(
            $group,
            \@remainingIdx,
            sub {
                # Don't auto trash things with sidecars
                return 1 if @{ $_->{sidecars} };

                # Discard versions of files in folder with wrong date
                my $date = $_->{dateTaken};
                if ($date) {
                    if ( $_->{fullPath} =~ /(\d{4})-(\d\d)-(\d\d).*[\/\\]/ ) {
                        if (   $1 == $date->year
                            && $2 == $date->month
                            && $3 == $date->day )
                        {
                            # Date is in the path
                            return 1;
                        }
                        else {
                            # A different date is in the path
                            return 0;
                        }
                    }
                    else {
                        # Path doesn't have date in it
                        return 0;
                    }
                }
                else {
                    # Item has no date
                    return 0;
                }
            }
        );

        # Discard -2, -3 versions of files
        filterIndicies(
            $group,
            \@remainingIdx,
            sub {
                # Don't auto trash things with sidecars
                return 1 if @{ $_->{sidecars} };
                for ( $_->{fullPath} ) {
                    return 0 if /[-\s]\d+\.\w+$/;
                    return 0 if /\s\(\d+\)\.\w+$/;
                }
                return 1;
            }
        );
    }

    # Now take everything that isn't in @reminingIdx and suggest trash it
    my @isTrashable = map { 1 } ( 0 .. $#$group );
    $isTrashable[$_] = 0 for @remainingIdx;
    for ( my $i = 0; $i < @$group; $i++ ) {
        push @autoCommands, "t$i" if $isTrashable[$i];
    }

    # If it's a short mov file next to a jpg or heic that's an iPhone,
    # then it's probably the live video portion from a burst shot. We
    # should just continue
    my $isShortMovieSidecar = sub {
        my ( $basename, $ext ) = split_ext( $_->{fullPath} );
        return 0 if defined $ext and lc $ext ne 'mov';
        return 0 unless exists $_->{md5Info} and exists $_->{md5Info}->{size};
        my $altSize = -s combine_ext( $basename, 'heic' );
        $altSize = -s combine_ext( $basename, 'jpg' ) unless defined $altSize;
        return 0 unless defined $altSize;
        return 2 * $altSize >= $_->{md5Info}->{size};
    };
    if ( all { $isShortMovieSidecar->() } @{$group}[@remainingIdx] ) {
        push @autoCommands, 'c';
    }

    # Appending continue command will auto skip to the next for full auto mode
    #push @autoCommands, 'c';
    return join ';', @autoCommands;
}

# ------------------------------------------------------------------------------
# generateFindDupeFilesAutoAction helper subroutine
sub filterIndicies {
    my ( $dataArrayRef, $indiciesArrayRef, $predicate ) = @_;
    my @idx = grep {
        local $_ = $dataArrayRef->[$_];
        my $result = $predicate->();
        $result
    } @$indiciesArrayRef;
    @$indiciesArrayRef = @idx if @idx;
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
sub buildFindDupeFilesPrompt {
    my ( $group, $defaultCommand ) = @_;

    # Build base of prompt - indexed paths
    my @prompt = ();

    # The list of all files in the group
    my @paths = map { pretty_path( $_->{fullPath} ) } @$group;

    # Start by building the header row, the formats for other rows follows this
    # Matches
    my $delim = ' ';
    push @prompt, ' ' x @$group, $delim;

    # Index
    my $indexFormat = "\%@{[length $#$group]}s.";
    push @prompt, sprintf( $indexFormat, '#' ), $delim;

    # Filename
    my $lengthBeforePath = length join '', @prompt;
    my $maxPathLength    = max( 64 - $lengthBeforePath, map { length } @paths );
    my $pathFormat       = "\%-${maxPathLength}s";
    push @prompt,
        sprintf( $pathFormat, 'File_name' . ( '_' x ( $maxPathLength - 9 ) ) ),
        $delim;

    # Metadata
    my $metadataFormat = "|$delim%-19s$delim|$delim%-19s$delim|$delim%s";
    push @prompt,
        sprintf( $metadataFormat,
        'Taken______________', 'Modified___________', 'Size' );
    push @prompt, "\n";
    for ( my $i = 0; $i < @$group; $i++ ) {
        my $elt  = $group->[$i];
        my $path = $paths[$i];

        # Matches
        for my $matchType ( @{ $elt->{matches} } ) {
            if ( $matchType == $MATCH_FULL ) {
                push @prompt, Term::ANSIColor::colored( 'F', 'black on_green' );
            }
            elsif ( $matchType == $MATCH_CONTENT ) {
                push @prompt,
                    Term::ANSIColor::colored( 'C', 'black on_yellow' );
            }
            elsif ( $matchType == $MATCH_NONE ) {
                push @prompt, Term::ANSIColor::colored( 'X', 'black on_red' );
            }
            else {
                push @prompt, '?';
            }
        }
        push @prompt, $delim;

        # Index
        push @prompt, colored_by_index( sprintf( $indexFormat, $i ), $i ),
            $delim;

        # Filename
        push @prompt, colored_by_index( sprintf( $pathFormat, $path ), $i ),
            $delim;

        # Metadata
        my ( $mtime, $size );
        if ( my $md5Info = $elt->{md5Info} ) {
            $mtime = $md5Info->{mtime};
            $size  = $md5Info->{size};
        }
        my $dateTaken =
            $elt->{dateTaken} ? $elt->{dateTaken}->strftime('%F %T') : '?';
        $mtime = $mtime ? POSIX::strftime( '%F %T', localtime $mtime ) : '?';
        $size  = $size  ? format_bytes($size)                          : '?';
        push @prompt, sprintf( $metadataFormat, $dateTaken, $mtime, $size );

        # Missing warning
        unless ( $elt->{exists} ) {
            push @prompt, $delim,
                Term::ANSIColor::colored( '[MISSING]', 'bold red on_white' );
        }

        # Wrong dir warning
        if ( $elt->{dateTaken} ) {
            my ( $vol, $dir, $filename ) = split_path( $elt->{fullPath} );
            my $parentDir = List::Util::first { $_ } reverse split_dir($dir);
            if ( $parentDir =~ /^(\d{4})-(\d\d)-(\d\d)/ ) {
                if (   $1 != $elt->{dateTaken}->year
                    || $2 != $elt->{dateTaken}->month
                    || $3 != $elt->{dateTaken}->day )
                {
                    push @prompt, $delim,
                        Term::ANSIColor::colored( '[WRONG DIR]',
                        'bold red on_white' );
                }
            }
        }
        push @prompt, "\n";

        # Collect all sidecars and add to prompt
        for ( @{ $elt->{sidecars} } ) {
            push @prompt,
                ' ' x $lengthBeforePath,
                colored_by_index( pretty_path($_), $i ),
                "\n";
        }
    }

    # Returns either something like 'x0/x1' or 'x0/.../x42'
    my $getMultiCommandOption = sub {
        my ($prefix) = @_;
        if ( @$group <= 3 ) {
            return join '/',
                map { colored_by_index( "$prefix$_", $_ ) } ( 0 .. $#$group );
        }
        else {
            return colored_by_index( "${prefix}0", 0 ) . '/.../'
                . colored_by_index( "$prefix$#$group", $#$group );
        }
    };

    # Input options
    push @prompt, 'Choose action(s): ?/c/d/', $getMultiCommandOption->('o'),
        '/q/', $getMultiCommandOption->('t'), ' ';
    if ($defaultCommand) {
        my @dcs = split( ';', $defaultCommand );
        @dcs = map { /^\w+(\d+)$/ ? colored_by_index( $_, $1 ) : $_ } @dcs;
        push @prompt, '[', join( ';', @dcs ), '] ';
    }
    return join '', @prompt;
}

1;
