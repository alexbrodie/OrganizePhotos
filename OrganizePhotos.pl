#!/usr/bin/perl
=pod
 
=head1 NAME
 
OrganizePhotos - utilities for managing a collection of photos/videos
 
=head1 SYNOPSIS
 
    OrganizePhotos.pl <verb> <options>
    OrganizePhotos.pl VerifyMd5
    OrganizePhotos.pl CheckMd5 [glob_pattern]
    OrganizePhotos.pl FindDupeFiles
 
=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.
 
=head2 VerifyMd5
 
Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.
 
MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:
filename: hash
 
This method is read-only, if you want to add/update MD5s, use CheckMd5.
 
=head2 CheckMd5 [glob_pattern]
 
For each media files under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

For each file matching glob_pattern, generate the MD5 hash and either
add to md5.txt file if missing or verify hashes match if already present.
 
This method is read/write, if you want to read-only MD5 checkin, 
 use VerifyMd5.
 
=head2 FindDupeFiles
 
Find files that have multiple copies
 
=head1 TODO
 
=head2 FindMisplacedFiles

Find files that aren't in a directory appropriate for their date
 
=head2 FindDupeFolders

Find the folders that represent the same date
 
=head2 FindMissingFiles

Finds files that may be missing based on gaps in sequential photos
 
=head2 FindMisplacedFiles

Find files that are in the wrong directory
 
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
use File::Spec::Functions qw(:ALL);
use Image::ExifTool;
use Pod::Usage;
use Term::ANSIColor;

# What we expect an MD5 hash to look like
my $md5pattern = qr/[0-9a-f]{32}/;

main();
exit 0;

#--------------------------------------------------------------------------
sub main {
    if ($#ARGV == -1 || ($#ARGV == 0 && $ARGV[0] =~ /[-\/][?h]/)) {
        pod2usage();
    } else {
        my $rawVerb = shift @ARGV;
        my $verb = lc $rawVerb;
        if ($verb eq 'verifymd5') {
            doVerifyMd5(@ARGV);
        } elsif ($verb eq 'checkmd5') {
            doCheckMd5(@ARGV);
        } elsif ($verb eq 'finddupefiles') {
            doFindDupeFiles(@ARGV);
        } elsif ($verb eq 'test') {
            doTest(@ARGV);
        } else {
            die "Unknown verb: $rawVerb\n";
        }
    }
}

#--------------------------------------------------------------------------
# Execute VerifyMd5 verb
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
# Execute CheckMd5 verb
sub doCheckMd5 {
    if ($#_ == -1) {
        # No args - check or add MD5s for all the media files
        # below the current dir
        local *wanted = sub {
            if (!-d) {
                #if (/\.(?:crw|cr2|m4v|mov|mp4|mts|nef|raf)$/i) {
                if (/\.(?:crw|cr2|jpeg|jpg|m4v|mov|mp4|mpg|mts|nef|raf)$/i) {
                    verifyOrGenerateMd5($_)
                } elsif ($_ ne 'md5.txt') {
                    # TODO: Also skip Thumbs.db, .Ds_Store, etc?
                    print "Skipping    MD5 for ", rel2abs($_), "\n";
                }
            }
        };
        find(\&wanted, '.');
    } else {
        # Glob(s) provided - check or add MD5s for all files that match
        verifyOrGenerateMd5($_) for sort map { glob } @_;
    }
}

#--------------------------------------------------------------------------
# Execute FindDupeFiles verb
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
        push(@{$md5ToPaths{$md5}}, $path);
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
        print "------\n";
        
        # If all in this group are JPEG...
        if (!grep { !/\.(?:jpeg|jpg)$/i } @$group) {
            # ...get each's whole file hashes match
            my @fullMd5s = map { getBareFileMd5($_) } @$group;
            for (my $i = 0; $i < @$group; $i++) {
                print "  $i. [", $fullMd5s[$i], "] ", diffColored($group->[$i], $i), "\n";
                # TODO: collect all sidecars and tell user
            }

            if (!grep { $_ ne $fullMd5s[0] } @fullMd5s) {
                # All the same
            } else {
                # A full file mismatch
            }
        } else {
            # At least one non-JPEG
            for (my $i = 0; $i < @$group; $i++) {
                print "  $i. ", diffColored($group->[$i], $i),, "\n";
                # TODO: collect all sidecars and tell user
            }
        }

        # TODO: if jpgs, use full file MD5 to see if they're binary
        #       equivalent and tell user
        
        unless ($all) {
            while (1) {
                print "Diff, Continue, Always continue, Trash Number (d/c/a";
                print '/', diffColored("t$_", $_) for (0..$#$group);
                print "? ";
                
                chomp(my $in = lc <STDIN>);
            
                if ($in eq 'd') {
                    metadataDiff(@$group);
                } elsif ($in eq 'c') {
                    last;
                } elsif ($in eq 'a') {
                    $all = 1;
                    last;
                } elsif ($in =~ /^t(\d+)$/i) {
                    
                    print "Trash $1\n";
                }
            }
        }
    }
    
    #while (my ($md5, $paths) = each %md5ToPaths) {
    #    if (@$paths > 1) {
    #        print "$md5 (", scalar @$paths, ")\n";
    #        print "\t$_\n" for @$paths;
    #    }
    #}
}

#--------------------------------------------------------------------------
# Execute Test verb
sub doTest {
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
# If the file's md5.txt file has a MD5 for the specified [path], this
# verifies it matches the current MD5.
#
# If the file's md5.txt file doesn't have a MD5 for the specified [path],
# this adds the [path]'s current MD5 to it.
sub verifyOrGenerateMd5 {
    my ($path) = @_;
    
    $path = rel2abs($path);
    my $actualMd5 = eval { getMd5($path); };
    if ($@) {
        # Can't get the MD5
        # TODO: for now, skip but we'll want something better in the future
        warn "UNAVAILABLE MD5 for $path: $@";
        return;
    }
    
    # The path to file that contains the MD5 info
    my $md5Path = catpath((splitpath($path))[0..1], 'md5.txt');
    
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
    # TODO: path platform independent parse
    $path =~ /([^\\\/]+)$/ or confess "Couldn't find file name from $path";
    my $key = lc $1;
    my $expectedMd5 = $md5s->{$key};
    if ($expectedMd5) {
        # It's there; verify the existing hash
        if ($expectedMd5 eq $actualMd5) {
            # Matches last recorded hash, nothing to do
            print "Verified    MD5 for $path\n";
            return;
        } else {
            # Mismatch, needs resolving...
            warn "MISMATCH OF MD5 for $path";
            
            while (1)
            {
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
        
        # TODO: Should we do this for TIFF as well?
        
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
sub getBareFileMd5 {
    my ($path) = @_;
    
    open(my $fh, '<:raw', $path) or confess "Couldn't open $path: $!";
    
    my $md5 = new Digest::MD5;
    $md5->addfile($fh);

    return getMd5Digest($md5);
}

#--------------------------------------------------------------------------
sub getMd5Digest() {
    my ($md5) = @_;
    
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$md5pattern/ or confess "unexpected MD5: $hexdigest";
    
    return $hexdigest;
}

#--------------------------------------------------------------------------
sub metadataDiff {
    my ($leftPath, $rightPath) = @_;
    
    my $leftItems = readMetadata($leftPath);
    my $rightItems = readMetadata($rightPath);
    
    my @delta = ();
    
    while (my ($key, $value) = each %$leftItems) {
        my $right = $rightItems->{$key};
        if (!defined $right or $right ne $value) {
            # Key is in left with missing or different value
            push(@delta, [$key, $value, $right]);
        }
    }
    
    while (my ($key, $value) = each %$rightItems) {
        if (!exists $leftItems->{$key}) {
            # Key is in right but not left
            push(@delta, [$key, undef, $value]);
        }
    }
    
    for (@delta) {
        print
            colored($_->[0] . ':', 'bold'), "\n",
            defined $_->[1] ? diffColored($_->[1], 0) : 'undef', "\n",
            defined $_->[2] ? diffColored($_->[2], 1) : 'undef', "\n",
            "\n";
    }
}

#-------------------------------------------------------------------------
sub readMetadata {
    my ($path) = @_;
    
    my $et = new Image::ExifTool;
    
    $et->ExtractInfo($path) or confess "Couldn't ExtractInfo for $path";
    
    # If this file can't hold XMP (i.e. not JPEG or TIFF), look for
    # XMP sidecar
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
# format a date (such as that returned by stat) into string form
sub formatDate {
    my ($sec, $min, $hour, $day, $mon, $year) = localtime $_[0];
    return sprintf '%04d-%02d-%02dT%02d:%02d:%02d',
    $year + 1900, $mon + 1, $day, $hour, $min, $sec;
}

#--------------------------------------------------------------------------
sub diffColored {
    my ($message, $index) = @_;

    my @colors = ('red', 'green');

    return colored($message, $colors[$index % scalar @colors]);
}
