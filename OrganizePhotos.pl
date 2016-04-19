#!/usr/bin/perl
=pod

=head1 NAME

OrganizePhotos - utilities for managing a collection of photos/videos

=head1 SYNOPSIS

    OrganizePhotos.pl <verb> <options>
    OrganizePhotos.pl add-md5
    OrganizePhotos.pl check-md5 [glob_pattern]
    OrganizePhotos.pl verify-md5
    OrganizePhotos.pl find-dupe-files
    OrganizePhotos.pl metadata-diff
    OrganizePhotos.pl collect-trash

=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:

    filename: hash

Metadata operations are powered by Image::ExifTool.

=head2 add-md5

Alias: a5

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

=head2 check-md5

Alias: c5

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write, if you want to read-only MD5 checkin,
use verify-md5.

=head2 check-md5 <glob_pattern>

Alias: c5

For each file matching glob_pattern, generate the MD5 hash and either
add to md5.txt file if missing or verify hashes match if already present.

This method is read/write, if you want to read-only MD5 checkin,
use verify-md5.

=head2 verify-md5

Alias: v5

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

=head2 find-dupe-files

Alias: fdf

Find files that have multiple copies under the current directory.

=head2 metadata-diff <files>

Alias: md

Do a diff of the specified media files (including their sidecar metadata).

=head2 collect-trash

Alias: ct

Looks recursively for .Trash subdirectories under the current directory
and moves that content to the current directory's .Trash perserving
directory structure.

For example if we had the following trash:

    ./Foo/.Trash/1.jpg
    ./Foo/.Trash/2.jpg
    ./Bar/.Trash/1.jpg

After collection we would have:

    ./.Trash/Foo/1.jpg
    ./.Trash/Foo/2.jpg
    ./.Trash/Bar/1.jpg

=head1 TODO

=head2 FindMisplacedFiles

Find files that aren't in a directory appropriate for their date
 
=head2 FindDupeFolders

Find the folders that represent the same date

=head2 FindMissingFiles

Finds files that may be missing based on gaps in sequential photos

=head2 FindScreenShots

Find files which are screenshots

=head2 FindOrphanedFiles

Find XMP or THM files that don't have a cooresponding main file

=head2 --if-modified-since

Flag for CheckMd5/VerifyMd5 to only check files created/modified since
the provided timestamp or timestamp at last MD5 check

=head1 AUTHOR

Copyright 2016, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool>

=cut

use strict;
use warnings;

use Carp qw(confess);
use Digest::MD5;
use File::Copy;
use File::Find;
use File::Glob qw(:globally :nocase);
use File::Path qw(make_path);
use File::Spec::Functions qw(:ALL);
use Image::ExifTool;
use Pod::Usage;
use Term::ANSIColor;

# What we expect an MD5 hash to look like
my $md5pattern = qr/[0-9a-f]{32}/;

# Media file extensions
my $mediaType = qr/\.(?i)(?:crw|cr2|jpeg|jpg|m4v|mov|mp4|mpg|mts|nef|raf)$/;

main();
exit 0;

#--------------------------------------------------------------------------
sub main {
    if ($#ARGV == -1 || ($#ARGV == 0 && $ARGV[0] =~ /[-\/][?h]/)) {
        pod2usage();
    } else {
        my $rawVerb = shift @ARGV;
        my $verb = lc $rawVerb;
        if ($verb eq 'add-md5' or $verb eq 'a5') {
            doAddMd5(@ARGV);
        } elsif ($verb eq 'check-md5' or $verb eq 'c5') {
            doCheckMd5(@ARGV);
        } elsif ($verb eq 'verify-md5' or $verb eq 'v5') {
            doVerifyMd5(@ARGV);
        } elsif ($verb eq 'find-dupe-files' or $verb eq 'fdf') {
            doFindDupeFiles(@ARGV);
        } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
            doMetadataDiff(@ARGV);
        } elsif ($verb eq 'collect-trash' or $verb eq 'ct') {
            doGatherTrash(@ARGV);
        } elsif ($verb eq 'test') {
            doTest(@ARGV);
        } else {
            die "Unknown verb: $rawVerb\n";
        }
    }
}

#--------------------------------------------------------------------------
# Execute verify-md5 verb
sub doVerifyMd5 {
    our $all = 0;
    local *callback = sub {
        my ($path, $expectedMd5) = @_;
        my $actualMd5 = getMd5($path);
        if ($actualMd5 eq $expectedMd5) {
            # Hash match
            print "Verified MD5 for $path\n";
        } else {
            # Has MIS-match, needs input
            warn "ERROR: MD5 mismatch for $path ($actualMd5 != $expectedMd5)\n";
            unless ($all) {
                while (1) {
                    print "Ingore, ignore All, Quit (i/a/q)? ";
                    chomp(my $in = lc <STDIN>);

                    if ($in eq 'i') {
                        last;
                    } elsif ($in eq 'a') {
                        $all = 1;
                        last;
                    } elsif ($in eq 'q') {
                        confess "MD5 mismatch for $path";
                    }
                }
            }
        }
    };
    findMd5s(\&callback, '.');
}

#--------------------------------------------------------------------------
# Execute add-md5 verb
sub doAddMd5 {
    verifyOrGenerateMd5Recursively(1);
}

#--------------------------------------------------------------------------
# Execute check-md5 verb
sub doCheckMd5 {
    if ($#_ == -1) {
        # No args - check or add MD5s for all the media files
        # below the current dir
        verifyOrGenerateMd5Recursively(0);
    } else {
        # Glob(s) provided - check or add MD5s for all files that match
        verifyOrGenerateMd5($_, 0) for sort map { glob } @_;
    }
}

#--------------------------------------------------------------------------
# Execute find-dupe-files verb
sub doFindDupeFiles {
    #local our %results = ();
    #local *wanted = sub {
    #    if (!-d && /^(.{4}\d{4}).*(\.[^.]*)$/) {
    #        push(@{$results{lc "$1$2"}}, $File::Find::name);
    #    }
    #};
    #find(\&wanted, '.');
    
    #for (sort keys %results) {
    #    my @result = @{$results{$_}};
    #    if (@result > 1) {
    #        print "$_ (@{[scalar @result]}) \n";
    #        print "  @{[getMd5($_)]} : $_\n" for @result;
    #    }
    #}

    # Make hash from MD5 to files with that MD5
    local our %md5ToPaths = ();
    local *callback = sub {
        my ($path, $md5) = @_;

        # Omit anything that is .Trash-ed
        my @dirs = splitdir((splitpath($path))[1]);
        unless (grep { /^\.Trash$/i } @dirs) {
            push(@{$md5ToPaths{$md5}}, $path);
        }
    };
    findMd5s(\&callback, '.');

    # Put everthing that has dupes in an array for sorting
    my @dupes = ();
    while (my ($md5, $paths) = each %md5ToPaths) {
        if (@$paths > 1) {
            push(@dupes, [sort @$paths]);
        }
    }

    # Sort groups by first element
    @dupes = sort { $a->[0] cmp $b->[0] } @dupes;

    my $all = 0;
    for my $group (@dupes) {

        # Filter out missing files
        # TODO: remove missing files from md5.txt?
        @$group = grep { -e } @$group;
        next unless @$group > 1;

        my @prompt;

        # If all in this group are JPEG...
        #if (!grep { !/\.(?:jpeg|jpg)$/i } @$group) {

        for (my $i = 0; $i < @$group; $i++) {
            my $path = $group->[$i];

            push @prompt, "  $i. ";

            # If MD5 isn't a whole file MD5, put compute the wholefile MD5 and add to output
            if ($path =~ /\.(?:jpeg|jpg)$/i) {
                push @prompt, '[', getBareFileMd5($path), '] ';
            }

            push @prompt, coloredByIndex($path, $i), getDirectoryError($path, $i), "\n";
            # TODO: collect all sidecars and tell user
        }

        print @prompt and next if $all;

        push @prompt, "Diff, Continue, Always continue, Trash Number, Open Number (d/c/a";
        for my $x ('t', 'o') {
            push @prompt, '/', coloredByIndex("$x$_", $_) for (0..$#$group);
        }
        push @prompt, ")? ";

        while (1) {
            print "\n", @prompt;
            chomp(my $in = lc <STDIN>);

            if ($in eq 'd') {
                # Diff
                metadataDiff(@$group);
            } elsif ($in eq 'c') {
                # Continue
                last;
            } elsif ($in eq 'a') {
                # Always continue
                $all = 1;
                last;
            } elsif ($in =~ /^t(\d+)$/i) {
                # Trash Number
                if ($1 < @$group) {
                    trashMedia($group->[$1]);
                    last;
                }
            } elsif ($in =~ /^o(\d+)$/i) {
                # Open Number
                if ($1 < @$group) {
                    `open "$group->[$1]"`;
                }
            }
        }
    }
}

#--------------------------------------------------------------------------
# Execute metadata-diff verb
sub doMetadataDiff {
    metadataDiff(@_);
}

#--------------------------------------------------------------------------
# Execute collect-trash verb
sub doCollectTrash {
}

#--------------------------------------------------------------------------
# Execute test verb
sub doTest {
    getDirectoryError(rel2abs($_)) for @_;
}

#--------------------------------------------------------------------------
# For each item in each md5.txt file under [dir], invoke [callback]
# passing it full path and MD5 hash as arguments like
#      callback($absolutePath, $md5AsString)
sub findMd5s {
    my ($callback, $dir) = @_;

    local *wanted = sub {
        if (!-d && lc $_ eq 'md5.txt') {
            open(my $fh, '<:crlf', $_) or confess "Couldn't open $File::Find::name: $!";
            my $md5s = readMd5FileFromHandle($fh);
            my $dir = $File::Find::dir;
            for (sort keys %$md5s) {
                $callback->(rel2abs(catpath($dir, $_)), $md5s->{$_});
            }
        }
    };
    find(\&wanted, $dir);
}

#--------------------------------------------------------------------------
# Call verifyOrGenerateMd5 for each media file under the current directory
sub verifyOrGenerateMd5Recursively {
    my ($addOnly) = @_;

    local *wanted = sub {
        if (!-d) {
            if (/$mediaType/) {
                verifyOrGenerateMd5($_, $addOnly)
            } elsif ($_ ne 'md5.txt') {
                # TODO: Also skip Thumbs.db, .Ds_Store, etc?
                print "Skipping    MD5 for ", rel2abs($_), "\n";
            }
        }
    };
    find(\&wanted, '.');
}

#--------------------------------------------------------------------------
# If the file's md5.txt file has a MD5 for the specified [path], this
# verifies it matches the current MD5.
#
# If the file's md5.txt file doesn't have a MD5 for the specified [path],
# this adds the [path]'s current MD5 to it.
sub verifyOrGenerateMd5 {
    my ($path, $addOnly) = @_;

    # The path to file that contains the MD5 info
    $path = rel2abs($path);
    my ($volume, $dir, $name) = splitpath($path);
    my $md5Path = catpath($volume, $dir, 'md5.txt');

    # Open MD5 file
    my $fh;
    my $md5s;
    if (open($fh, '+<:crlf', $md5Path)) {
        # Read existing contents
        $md5s = readMd5FileFromHandle($fh);
    } else {
        # File doesn't exist, open for write
        open($fh, '>', $md5Path) or confess "Couldn't open $md5Path: $!";
    }

    # Try lookup into MD5 file contents
    my $key = lc $name;
    my $expectedMd5 = $md5s->{$key};

    # In add-only mode, don't compute the hash of a file that
    # is already in the md5.txt
    if ($addOnly and $expectedMd5) {
        return;
    }

    # Get the actual MD5 by reading the whole file
    my $actualMd5 = eval { getMd5($path); };
    if ($@) {
        # Can't get the MD5
        # TODO: for now, skip but we'll want something better in the future
        warn "UNAVAILABLE MD5 for $path: $@";
        return;
    }
    if ($expectedMd5) {
        # It's there; verify the existing hash
        if ($expectedMd5 eq $actualMd5) {
            # Matches last recorded hash, nothing to do
            print "Verified    MD5 for $path\n";
            return;
        } else {
            # Mismatch, needs resolving...
            warn "MISMATCH OF MD5 for $path";

            while (1) {
                print "Ignore, Overwrite, Quit (i/o/q)? ";
                chomp(my $in = lc <STDIN>);

                if ($in eq 'i') {
                    # Ignore the error and return
                    return;
                } elsif ($in eq 'o') {
                    # Exit loop to fall through to save actualMd5
                    last;
                } elsif ($in eq 'q') {
                    # User requested to terminate
                    confess "MD5 mismatch for $path";
                }
            }
        }
    } else {
        # It wasn't there, it's a new file, we'll add that
        print "ADDING      MD5 for $path\n";
    }

    # Add/update MD5
    $md5s->{$key} = $actualMd5;

    # Clear MD5 file
    seek($fh, 0, 0);
    truncate($fh, 0);

    # Update MD5 file
    for (sort keys %$md5s) {
        print $fh lc $_, ': ', $md5s->{$_}, "\n";
    }
}

#--------------------------------------------------------------------------
# Removes the cached MD5 hash for the specified path
sub removeMd5ForPath {
    my ($path) = @_;

    # The path to file that contains the MD5 info
    my ($volume, $dir, $name) = splitpath($path);
    my $md5Path = catpath($volume, $dir, 'md5.txt');

    if (open(my $fh, '+<:crlf', $md5Path)) {
        my @old = <$fh>;
        my @new = grep { !/\Q$name\E:/i } @old;

        if (@old != @new) {
            seek($fh, 0, 0);
            truncate($fh, 0);
            print $fh @new;

            print "Removed $name from $md5Path\n";
        }
    }
}

#--------------------------------------------------------------------------
# Deserialize a md5.txt file handle into a filename -> MD5 hash
sub readMd5FileFromHandle {
    my ($fh) = @_;
    
    my %md5s = ();
    for (<$fh>) {
        chomp;
        $_ = lc $_;
        /^([^:]+):\s*($md5pattern)$/ or warn "unexpected line in MD5: $_";

        $md5s{lc $1} = $2;
    }
    
    return \%md5s;
}

#--------------------------------------------------------------------------
# Calculates and returns the MD5 digest of a (set of) file(s). For JPEG
# files, this skips the metadata portion of the files and only computes
# the hash for the pixel data.
sub getMd5 {
    use Digest::MD5;
    
    my $md5 = new Digest::MD5;
    
    for my $path (@_) {
        open(my $fh, '<:raw', $path) or confess "Couldn't open $path: $!";
        
        #my $modified = formatDate((stat($fh))[9]);
        #print "Date modified: $modified\n";

        # TODO: Should we do this for TIFF, DNG as well?

        # If JPEG, skip metadata which may change and only hash pixel data
        # and hash from Start of Scan [SOS] to end
        if ($path =~ /\.(?:jpeg|jpg)$/i) {
            # Read Start of Image [SOI]
            read($fh, my $soiData, 2) or confess "Failed to read SOI from $path: $!";
            my ($soi) = unpack('n', $soiData);
            $soi == 0xffd8 or confess "File didn't start with SOI marker: $path";

            # Read blobs until SOS
            my $tags = '';
            while (1) {
                read($fh, my $data, 4) or confess "Failed to read from $path at @{[tell $fh]} after $tags: $!";
                my ($tag, $size) = unpack('nn', $data);

                $tags .= sprintf("%04x,%04x;", $tag, $size);
                #printf("@%08x: %04x, %04x\n", tell($fh) - 4, $tag, $size);

                last if $tag == 0xffda;
                
                my $address = tell($fh) + $size - 2;
                seek($fh, $address, 0) or confess "Failed to seek $path to $address: $!";
            }
        }

        $md5->addfile($fh);
    }
    
    return getMd5Digest($md5);
}

#--------------------------------------------------------------------------
# Computes the MD5 for a full file
sub getBareFileMd5 {
    my ($path) = @_;
    
    open(my $fh, '<:raw', $path) or confess "Couldn't open $path: $!";
    
    my $md5 = new Digest::MD5;
    $md5->addfile($fh);

    return getMd5Digest($md5);
}

#--------------------------------------------------------------------------
# Get/verify/canonicalize hash from a Digest::MD5 object
sub getMd5Digest {
    my ($md5) = @_;
    
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$md5pattern/ or confess "unexpected MD5: $hexdigest";
    
    return $hexdigest;
}

#--------------------------------------------------------------------------
# Print all the metadata values which differ in a set of paths
sub metadataDiff {
    my @paths = @_;
    
    my @items = map { readMetadata($_) } @paths;
    
    # Collect all the keys which whose values aren't all equal
    my %keys = ();
    for (my $i = 0; $i < @items; $i++) {
        while (my ($key, $value) = each %{$items[$i]}) {
            for (my $j = 0; $j < @items; $j++) {
                if ($i != $j and
                    (!exists $items[$j]->{$key} or
                     $items[$j]->{$key} ne $value)) {
                    $keys{$key} = 1;
                    last;
                }
            }
        }
    }

    # Pretty print all the keys and associated values
    # which differ
    for my $key (sort keys %keys) {
        print colored("$key:", 'bold'), ' ' x (29 - length $key);
        for (my $i = 0; $i < @items; $i++) {
            print coloredByIndex(exists $items[$i]->{$key}
                ? $items[$i]->{$key}
                : colored('undef', 'faint'), $i),
            "\n", ' ' x 30;
        }
        print "\n";
    }
}

#-------------------------------------------------------------------------
# Read metadata as an ExifTool hash for the specified path (and any
# XMP sidecar when appropriate)
sub readMetadata {
    my ($path) = @_;

    my $et = new Image::ExifTool;

    $et->ExtractInfo($path) or confess "Couldn't ExtractInfo for $path";

    # If this file can't hold XMP (i.e. not JPEG or TIFF), look for
    # XMP sidecar
    # TODO: Should we exclude DNG here too?
    if ($path !~ /\.(jpeg|jpeg|tif|tiff)$/i) {
        (my $xmpPath = $path) =~ s/[^.]*$/xmp/;
        if (-s $xmpPath) {
            $et->ExtractInfo($xmpPath) or confess "Couldn't ExtractInfo for $xmpPath";
        }
    }

    my $info = $et->GetInfo();
    #my $keys = $et->GetTagList($info);

    return $info;
}

#--------------------------------------------------------------------------
sub getDirectoryError {
    my ($path, $colorIndex) = @_;

    my $et = new Image::ExifTool;

    my @dateProps = qw(DateTimeOriginal MediaCreateDate);

    my $info = $et->ImageInfo($path, \@dateProps, {DateFormat => '%F'});

    my $date;
    for (@dateProps) {
        if (exists $info->{$_}) {
            $date = $info->{$_};
            last;
        }
    }

    if (!defined $date) {
        warn "Couldn't find date for $path";
        return '';
    }

    my $yyyy = substr $date, 0, 4;
    my $date2 = join '', $date =~ /^..(..)-(..)-(..)$/;
    my @dirs = splitdir((splitpath($path))[1]);
    if ($dirs[-3] eq $yyyy and
        $dirs[-2] =~ /^(?:$date|$date2)/) {
        # Falsy empty string when path is correct
        return '';
    } else {
        # Truthy error string
        my $backColor = defined $colorIndex ? colorByIndex($colorIndex) : 'red';
        return ' ' . colored("** Wrong dir! [$date] **", "bright_white on_$backColor") . ' ';
    }
}

#--------------------------------------------------------------------------
# Trash the specified path and any sidecars
sub trashMedia {
    my ($path) = @_;
    #print qq(trashMedia("$path");\n);

    # Note that this assumes a proper extension
    (my $query = $path) =~ s/[^.]*$/*/;
    trashFile($_) for glob qq("$query");
}

#--------------------------------------------------------------------------
# Trash the specified path by moving it to a .Trash subdir and removing
# its entry from the md5.txt file
sub trashFile {
    my ($path) = @_;
    #print qq(trashFile("$path");\n);

    my ($volume, $dir, $name) = splitpath($path);
    my $trashDir = catpath($volume, $dir, '.Trash');
    my $trashPath = catfile($trashDir, $name);

    #print qq("$path" -> "$trashPath"\n);
    -d $trashDir or make_path($trashDir) or confess "Failed to make directory $trashDir: $!";
    move($path, $trashPath) or confess "Failed to move $path to $trashPath: $!";
    print "Moved $path\n   to $trashPath\n";

    removeMd5ForPath($path);
}

#--------------------------------------------------------------------------
# Format a date (such as that returned by stat) into string form
sub formatDate {
    my ($sec, $min, $hour, $day, $mon, $year) = localtime $_[0];
    return sprintf '%04d-%02d-%02dT%02d:%02d:%02d',
                $year + 1900, $mon + 1, $day, $hour, $min, $sec;
}

#--------------------------------------------------------------------------
# Colorizes text for diffing purposes
sub coloredByIndex {
    my ($message, $colorIndex) = @_;

    return colored($message, colorByIndex($colorIndex));
}

#--------------------------------------------------------------------------
sub colorByIndex {
    my ($colorIndex) = @_;

    my @colors = ('red', 'green', 'magenta', 'cyan', 'yellow', 'blue');
    return $colors[$colorIndex % scalar @colors];
}
