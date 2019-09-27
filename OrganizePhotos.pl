#!/usr/bin/perl
#
# Commands to regenerate documentation:
#   pod2markdown OrganizePhotos.pl > README.md
#
# TODO LIST
#  * !! when trashing a dupe, make sure not to trash sidecars that don't match
#  * glob in friendly sort order
#  * add prefix/coloring to operations output to differntate (move, trash, etc)
#  * look for zero duration videos (this hang's Lightroom's
#    DynamicLinkMediaServer which pegs the CPU and blocks Lr preventing any
#    video imports or other things requiring DLMS, e.g. purging video cache)
#  * get rid of texted photos (no metadata (e.g. camera make & model), small 
#    files)
#  * also report base name match when resolving groups
#  * content only match for mov, png, tiff, png
#  * undo support (z)
#  * get dates for HEIC. maybe just need to update ExifTools?
#  * should notice new MD5 in one dir and missing MD5 in another dir with
#    same file name for when files are moved outside of this script, e.g.
#    Lightroom imports from ToImport folder as move
#  * Offer to trash short sidecar movies with primary image tagged 'NoPeople'?
#  * Consolidate filename/ext handling, e.g. the regex \.([^.]*)$
#  * Consolidate formatting (view) options for file operations output
#
=pod

=head1 NAME

OrganizePhotos - utilities for managing a collection of photos/videos

=head1 SYNOPSIS

    # Help:
    OrganizePhotos.pl -h

    # Typical workflow:
    # Import via Image Capture to local folder as originals (unmodified copy)
    # Import that folder in Lightroom as move
    OrganizePhotos.pl checkup /photos/root/dir
    # Archive /photos/root/dir (see help)

=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:

    filename: hash

Metadata operations are powered by Image::ExifTool.

The calling pattern for each command follows the pattern:

    OrganizePhotos.pl <verb> [options...]

The following verbs are available:

=over 5

=item B<add-md5> [glob patterns...]

=item B<append-metadata> <target file> <source files...>

=item B<check-md5> [glob patterns...]

=item B<checkup> [-a] [-d] [-l] [-n] [glob patterns...]

=item B<collect-trash> [glob patterns...]

=item B<consolodate-metadata> <dir>

=item B<find-dupe-dirs>

=item B<find-dupe-files> [-a] [-d] [-l] [-n] [glob patterns...]

=item B<metadata-diff> <files...>

=item B<remove-empties> [glob patterns...]

=item B<verify-md5> [glob patterns...]

=back

=head2 add-md5 [glob patterns...]

I<Alias: a5>

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

This does not modify media files or their sidecars, it only adds entries
to the md5.txt files.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 check-md5 [glob patterns...]

I<Alias: c5>

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write for MD5s, if you want to perform read-only
MD5 checks (i.e., don't write to md5.txt), then use verify-md5.

This does not modify media files or their sidecars, it only modifies
the md5.txt files.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head3 Examples

    # Check or add MD5 for all CR2 files in the current directory
    $ OrganizePhotos.pl c5 *.CR2

=head2 checkup [glob patterns...]

I<Alias: c>

This command runs the following suggested suite of commands:

    check-md5 [glob patterns...]
    find-dupe-files [-a | --always-continue] [glob patterns...]
    remove-empties [glob patterns...]
    collect-trash [glob patterns...]

=head3 Options

=over 24

=item B<-a, --always-continue>

Always continue

=item B<-d, --auto-diff>

Automatically do the 'd' diff command for every new group of files

=item B<-l, --default-last-action>

Enter repeats last command

=item B<-n, --by-name>

Search for items based on name rather than the default of MD5

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 collect-trash [glob patterns...]

I<Alias: ct>

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

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 consolodate-metadata <dir>

I<Alias: cm>

Not yet implemented

=head2 find-dupe-dirs

I<Alias: fdd>

Find directories that represent the same date.

=head2 find-dupe-files [  patterns...]

I<Alias: fdf>

Find files that have multiple copies under the current directory.

=head3 Options

=over 24

=item B<-a, --always-continue>

Always continue

=item B<-d, --auto-diff>

Automatically do the 'd' diff command for every new group of files

=item B<-l, --default-last-action>

Enter repeats last command

=item B<-n, --by-name>

Search for items based on name rather than the default of MD5

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 metadata-diff <files...>

I<Alias: md>

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

=head3 Options

=over 24

=item B<-x, --exclude-sidecars>

Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
include any metadata from a sidecar XMP which typically is the place where
user added tags like rating and keywords are placed.

=back

=head2 remove-empties [glob patterns...]

I<Alias: re>

Remove any subdirectories that are empty save an md5.txt file.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 verify-md5 [glob patterns...]

I<Alias: v5>

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

This method does not modify any file.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=begin comment

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

=end comment

=head1 Related commands

=head2 Complementary ExifTool commands

    # Append all keyword metadata from SOURCE to DESTINATION
    exiftool -addTagsfromfile SOURCE -HierarchicalSubject -Subject DESTINATION

    # Shift all mp4 times, useful when clock on GoPro is reset to 1/1/2015 due to dead battery
    # Format is: offset='[y:m:d ]h:m:s' or more see https://sno.phy.queensu.ca/~phil/exiftool/Shift.html#SHIFT-STRING
    offset='4:6:24 13:0:0'
    exiftool "-CreateDate+=$offset" "-ModifyDate+=$offset" 
             "-TrackCreateDate+=$offset" "-TrackModifyDate+=$offset" 
             "-MediaCreateDate+=$offset" "-MediaModifyDate+=$offset" *.mp4
    
=head2 Complementary Mac commands

    # Mirror SOURCE to TARGET
    rsync -ah --delete --delete-during --compress-level=0 --inplace --progress 
        SOURCE TARGET

    # Move .Trash directories recursively to the trash
    find . -type d -iname '.Trash' -exec trash {} \;

    # Delete .DS_Store recursively (omit "-delete" to only print)
    find . -type f -name .DS_Store -print -delete

    # Delete zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -iname md5.txt -empty -print -delete

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        -or -iname "md5.txt" \) -print -exec chmod -x {} \;

    # Remove downloaded-and-untrusted extended attribute for the current tree
    xattr -d -r com.apple.quarantine .

    # Find large-ish files
    find . -size +100MB

    # Display disk usage stats sorted by size decreasing
    du *|sort -rn

    # For each HEIC move some metadata from neighboring JPG to XMP sidecar
    # and trash the JPG. This is useful when you have both the raw HEIC from
    # iPhone and the converted JPG which holds the metadata and you want to
    # move it to the HEIC and just keep that. For example if you import once
    # as JPG, add metadata, and then re-import as HEIC.
    find . -iname '*.heic' -exec sh -c 'x="{}"; y=${x:0:${#x}-4}; exiftool -tagsFromFile ${y}jpg -Rating -Subject -HierarchicalSubject ${y}xmp; trash ${y}jpg' \;

    # For each small MOV file, look for pairing JPG or HEIC files and print
    # the path of the MOV files where the main image file is missing.
    find . -iname '*.mov' -size -6M -execdir sh -c 'x="{}"; y=${x:0:${#x}-3}; [[ -n `find . -iname "${y}jpg" -o -iname "${y}heic"` ]] || echo "$PWD/$x"' \;

    # Restore _original files (undo exiftool changes)
    find . -iname '*_original' -exec sh -c 'x={}; y=${x:0:${#x}-9}; echo mv $x $y' \;

=head2 Complementary PC commands

    # Mirror SOURCE to TARGET
    robocopy /MIR SOURCE TARGET

=head1 AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool>

=cut

# ★★★★★
# ★★★★☆
# ★★★☆☆
# ★★☆☆☆
# ★☆☆☆☆

use strict;
use warnings;

use Carp qw(confess);
use Data::Compare;
use Data::Dumper;
use DateTime::Format::HTTP;
use Digest::MD5;
use File::Compare;
use File::Copy;
use File::Find;
use File::Glob qw(:globally :nocase);
use File::Path qw(make_path);
use File::Spec::Functions qw(:ALL);
use File::stat;
use Getopt::Long;
use Image::ExifTool;
use JSON;
use Pod::Usage;
use Term::ANSIColor;

# What we expect an MD5 hash to look like
my $md5pattern = qr/[0-9a-f]{32}/;

# TODO - consolidate extension checks here as much as possible

# Media file extensions
my $mediaType = qr/
    # Media extension
    (?: \. (?i) (?:avi|crw|cr2|jpeg|jpg|heic|m4v|mov|mp4|mpg|mts|nef|png|psb|psd|raf|tif|tiff) $)
    | # Backup file
    (?: [._] (?i) bak\d* $)
    /x;
    
# Map of extension to pointer to array of extensions of possible sidecars
# TODO: flesh this out
my %sidecarTypes = (
    AVI     => [],
    CRW     => [qw( JPEG JPG XMP )],
    CR2     => [qw( JPEG JPG XMP )],
    JPEG    => [],
    JPG     => [qw( MOV )],
    HEIC    => [qw( MOV XMP )],
    M4V     => [],
    MOV     => [],
    MP4     => [],
    MPG     => [],
    MTS     => [],
    NEF     => [qw( JPEG JPG XMP )],
    PNG     => [],
    PSB     => [],
    PSD     => [],
    RAF     => [qw( JPEG JPG XMP )],
    TIF     => [],
    TIFF    => []
);
    
# For extra output
my $verbosity = 0;
use constant VERBOSITY_2 => 2;
use constant VERBOSITY_DEBUG => 999;

main();
exit 0;

#===============================================================================
# Main entrypoint that parses command line a bit and routes to the 
# subroutines starting with "do"
sub main {
    # Parse args (using GetOptions) and delegate to the doVerb methods...
    if ($#ARGV == -1) {
        pod2usage();        
    } elsif ($#ARGV == 0 and $ARGV[0] =~ /^-[?h]$/i) {
        pod2usage(-verbose => 2);
    } else {
        Getopt::Long::Configure('bundling');
        my $rawVerb = shift @ARGV;
        my $verb = lc $rawVerb;
        if ($verb eq 'add-md5' or $verb eq 'a5') {
            GetOptions();
            doAddMd5(@ARGV);
        } elsif ($verb eq 'append-metadata' or $verb eq 'am') {
            GetOptions();
            doAppendMetadata(@ARGV);
        } elsif ($verb eq 'check-md5' or $verb eq 'c5') {
            GetOptions();
            doCheckMd5(@ARGV);
        } elsif ($verb eq 'checkup' or $verb eq 'c') {
            my ($all, $autoDiff, $byName, $defaultLastAction);
            GetOptions('always-continue|a' => \$all,
                       'auto-diff|d' => \$autoDiff,
                       'by-name|n' => \$byName,
                       'default-last-action|l' => \$defaultLastAction);
            doCheckMd5(@ARGV);
            doFindDupeFiles($all, $byName, $autoDiff, $defaultLastAction, @ARGV);
            doRemoveEmpties(@ARGV);
            doCollectTrash(@ARGV);
        } elsif ($verb eq 'collect-trash' or $verb eq 'ct') {
            GetOptions();
            doCollectTrash(@ARGV);
        } elsif ($verb eq 'consolodate-metadata' or $verb eq 'cm') {
            GetOptions();
            doConsolodateMetadata(@ARGV);
        } elsif ($verb eq 'find-dupe-dirs' or $verb eq 'fdd') {
            GetOptions();
            @ARGV and die "Unexpected parameters: @ARGV";
            doFindDupeDirs();
        } elsif ($verb eq 'find-dupe-files' or $verb eq 'fdf') {
            my ($all, $autoDiff, $byName, $defaultLastAction);
            GetOptions('always-continue|a' => \$all,
                       'auto-diff|d' => \$autoDiff,
                       'by-name|n' => \$byName,
                       'default-last-action|l' => \$defaultLastAction);
            doFindDupeFiles($all, $byName, $autoDiff, $defaultLastAction, @ARGV);
        } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
            my ($excludeSidecars);
            GetOptions('exclude-sidecars|x' => \$excludeSidecars);
            doMetadataDiff($excludeSidecars, @ARGV);
        } elsif ($verb eq 'remove-empties' or $verb eq 're') {
            GetOptions();
            doRemoveEmpties(@ARGV);
        } elsif ($verb eq 'test') {
            doTest();
        } elsif ($verb eq 'verify-md5' or $verb eq 'v5') {
            GetOptions();
            doVerifyMd5(@ARGV);
        } else {
            die "Unknown verb: $rawVerb\n";
        }
    }
}

# API ==========================================================================
# Execute add-md5 verb
sub doAddMd5 {
    verifyOrGenerateMd5ForGlob(1, 1, @_);
}

# API ==========================================================================
# Execute append-metadata verb
sub doAppendMetadata {
    appendMetadata(@_);
}

# API ==========================================================================
# Execute check-md5 verb
sub doCheckMd5 {
    verifyOrGenerateMd5ForGlob(0, 0, @_);
}

# API ==========================================================================
# Execute collect-trash verb
sub doCollectTrash {
    my (@globPatterns) = @_;
    
    traverseGlobPatterns(sub {
        my ($fileName, $root) = @_;
        
        if (-d $fileName and lc $fileName eq '.trash') {
            # Convert $root/bunch/of/dirs/.Trash to $root/.Trash/bunch/of/dirs
            my $oldFullPath = rel2abs($fileName);
            my $oldRelPath = abs2rel($oldFullPath, $root);
            my @dirs = splitdir($oldRelPath);
            @dirs = ('.Trash', (grep { lc ne '.trash' } @dirs));
            my $newRelPath = catdir(@dirs);
            my $newFullPath = rel2abs($newRelPath, $root);

            if ($oldFullPath ne $newFullPath) {
                # BUGBUG - this should probably strip out any extra .Trash
                # right now occasionally seeing things like
                # .Trash/foo/.Trash/bar.jpg
                moveDir($oldFullPath, $newFullPath);
            } else {
                #print "Noop for path $oldRelPath\n";
            }
        }
    }, 0, @globPatterns);
}

# API ==========================================================================
# Execute consolodate-metadata verb
sub doConsolodateMetadata {
    my ($arg1, $arg2, $etc) = @_;
    # TODO
}

# API ==========================================================================
# Execute find-dupe-dirs verb
sub doFindDupeDirs {

    my %keyToPaths = ();
    find({
        preprocess => \&preprocessSkipTrash,
        wanted => sub {
            if (-d and (/^(\d\d\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)(\d\d)(\d\d)\b/)) {
                    
                my $y = $1 < 20 ? $1 + 2000 : $1 < 100 ? $1 + 1900 : $1;                
                push @{$keyToPaths{lc "$y-$2-$3"}}, rel2abs($_);
            }
        }
    }, '.');
    
    #while (my ($key, $paths) = each %keyToPaths) {
    for my $key (sort keys %keyToPaths) {
        my $paths = $keyToPaths{$key};
        if (@$paths > 1) {
            print "$key:\n";
            print "\t$_\n" for @$paths;
        }
    }
}

# API ==========================================================================
# Execute find-dupe-files verb
sub doFindDupeFiles {
    my ($all, $byName, $autoDiff, $defaultLastAction, @globPatterns) = @_;
    
    my $fast = 0; # avoid slow operations, potentially with less precision?
    
    # Create the initial groups
    my %keyToPaths = ();
    if ($byName) {
        # Make hash from filename components to files that have that base name
        traverseGlobPatterns(sub {
            if (-f and /$mediaType/) { 
                my $path = rel2abs($_);
                my @splitPath = deepSplitPath($path);
                my ($name, $ext) = pop(@splitPath) =~ /^(.*)\.([^.]*)/;
                
                #print join('%', @splitPath), ";name=$name;ext=$ext;\n";

                # Start with extension
                #my $key = lc ($path =~ /\.([^\/\\.]*)$/)[0];
                my $key = lc $ext . ';';

                # Add basename
                my $nameRegex = qr/^
                    (
                        # things like DCF_1234
                        [a-zA-Z\d_]{4} \d{4} |
                        # things like 2009-08-11 12_31_45
                        \d{4} [-_] \d{2} [-_] \d{2} [-_\s] \d{2} [-_] \d{2} [-_] \d{2}
                    ) \b /x;

                if ($name =~ /$nameRegex/) {
                    $key .= lc $1 . ';';
                } else {
                    # Unknown file format, just use filename?
                    warn "Unknown filename format: $name";
                    $key .= lc $name . ';';
                }

                # parent dir should be similar (based on date format)
                my $dirRegex = qr/^
                    # yyyy-mm-dd or yy-mm-dd or yyyymmdd or yymmdd
                    (?:19|20)?(\d{2}) [-_]? (\d{2}) [-_]? (\d{2}) \b
                    /x;

                my $dirKey = '';
                for (reverse @splitPath) {
                    if (/$dirRegex/) {
                        $dirKey = lc "$1$2$3;";
                        last;
                    }
                }
                
                if ($dirKey) {
                    $key .= $dirKey;
                } else {
                    warn "Unknown directory format: $path\n";
                }

                #print "KEY($key) = VALUE($path);\n";
                push @{$keyToPaths{$key}}, $path;
            }
        }, 1, @globPatterns);
        
    } else {
        # Make hash from MD5 to files with that MD5
        findMd5s(sub {
            my ($path, $md5) = @_;
            push @{$keyToPaths{$md5}}, $path;
        }, @globPatterns);
    }

    # Put everthing that has dupes in an array for sorting
    my @dupes = ();
    while (my ($md5, $paths) = each %keyToPaths) {
        if (@$paths > 1) {
            if (@$paths > 1) {
                push @dupes, [sort {
                    # Try to sort paths trying to put the most likely
                    # master copies first and duplicates last

                    my (undef, @as) = deepSplitPath($a);
                    my (undef, @bs) = deepSplitPath($b);

                    for (my $i = 0; $i < @as; $i++) {
                        # If A is in a subdir of B, then B goes first
                        return 1 if $i >= @bs;

                        my ($aa, $bb) = ($as[$i], $bs[$i]);
                        if ($aa ne $bb) {
                            if ($aa =~ /^\Q$bb\E(.+)/) {
                                # A is a substring of B, put B first
                                return -1;
                            } elsif ($bb =~ /^\Q$aa\E(.+)/) {
                                # B is a substring of A, put A first
                                return 1;
                            }

                            # Try as filename and extension
                            my ($an, $ae) = $aa =~ /^(.*)\.([^.]*)$/;
                            my ($bn, $be) = $bb =~ /^(.*)\.([^.]*)$/;
                            if (defined $ae and defined $be and $ae eq $be) {
                                if ($an =~ /^\Q$bn\E(.+)/) {
                                    # A's filename is a substring of B's, put A first
                                    return 1;
                                } elsif ($bn =~ /^\Q$an\E(.+)/) {
                                    # B's filename is a substring of A's, put B first
                                    return -1;
                                }
                            }

                            return $aa cmp $bb;
                        }
                    }

                    # If B is in a subdir of be then B goes first
                    # else they are equal
                    return @bs > @as ? -1 : 0;
                } @$paths];
            }
        }
    }

    # Sort groups by first element with JPG last, raw files first
    my %extOrder = ( CRW => -1, CR2 => -1, HEIC => -1, NEF => -1, RAF => -1, JPG => 1, JPEG => 1 );
    @dupes = sort { 
        my ($an, $ae) = $a->[0] =~ /^(.*)\.([^.]*)$/;
        my ($bn, $be) = $b->[0] =~ /^(.*)\.([^.]*)$/;

        # Sort by filename first
        my $cmp = $an cmp $bn;
        return $cmp if $cmp;

        # Sort by extension (by extOrder, rather than alphabetic)
        my $aOrder = $extOrder{uc $ae} || 0;
        my $bOrder = $extOrder{uc $be} || 0;
        return $aOrder <=> $bOrder;
    } @dupes;
    
    # TODO: merge sidecars
    
    # Process each group of dupliates
    my $lastCommand = '';
    DUPES: for (my $dupeIndex = 0; $dupeIndex < @dupes; $dupeIndex++) {
        # Convert current element from an array of paths (strings) to
        # an array (per file, in storted order) to array of hash
        # references with some metadata in the same (desired) order
        my @group = map {
            { path => $_, exists => -e }
        } @{$dupes[$dupeIndex]};
        
        # If dupes are missing, we can auto-remove
        my $autoRemoveMissingDuplicates = 1;
        if ($autoRemoveMissingDuplicates) {
            # If there's missing files but at least one not missing...
            my $numMissing = grep { !$_->{exists} } @group;
            if ($numMissing > 0 and $numMissing < @group) {
                # Remove the metadata for all missing files, and
                # keep track of what's still existing
                my @newGroup = ();
                for (@group) {
                    if ($_->{exists}) {
                        push @newGroup, $_;
                    } else {
                        removeMd5ForPath($_->{path});
                    }
                }
            
                # If there's still multiple in the group, continue
                # with what was left over, else move to next group
                next DUPES if @newGroup < 2;
                @group = @newGroup;
            }
        }

        # Except when trying to be fast, calculate the MD5 match
        my $reco = '';
        unless ($fast) {
            # Want to tell if the files are identical, so we need hashes
            #my @md5Info = map { getMd5($_) } @group;
            # TODO: if we're not doing this by name we can use the md5.txt file contents for  MD5 and other metadata
            $_->{exists} and $_ = { %$_, %{getMd5($_->{path})} } for @group;
        
            my $fullMd5Match = 1;
            my $md5Match = 1;
        
            # If all the primary MD5s are the same report IDENTICAL
            # If any are missing, should be complete mismatch
            my $md5 = $group[0]->{md5} || 'x';
            my $fullMd5 = $group[0]->{full_md5} || 'x';
            for (my $i = 1; $i < @group; $i++) {
                $md5Match = 0 if $md5 ne ($group[$i]->{md5} || 'y');
                $fullMd5Match = 0 if $fullMd5 ne ($group[$i]->{full_md5} || 'y');
            }
        
            if ($fullMd5Match) {
                $reco = colored('[Match: FULL]', 'bold blue on_white');
            } elsif ($md5Match) {
                $reco = '[Match: Content]';
            } else {
                $reco = colored('[Match: UNKNOWN]', 'bold red on_white');
            }
        }
        
        # Build base of prompt - indexed paths
        my @prompt = ('Resolving ', ($dupeIndex + 1), ' of ', scalar @dupes, ' ', $reco, "\n");
        for (my $i = 0; $i < @group; $i++) {
            my $elt = $group[$i];

            push @prompt, "  $i. ";

            my $path = $elt->{path};
            push @prompt, coloredByIndex($path, $i);
            
            # Add file error suffix
            if ($elt->{exists}) {
                # Don't bother cracking the file to get metadata if we're in ignore all or fast mode
                push @prompt, getDirectoryError($path, $i) unless $all or $fast;                
            } else {
                push @prompt, ' ', colored('[MISSING]', 'bold red on_white');
            }
            
            push @prompt, "\n";
            
            # Collect all sidecars and add to prompt
            for (getSidecarPaths($path)) {
                if (lc ne lc $path) {
                    push @prompt, '     ', coloredByIndex(coloredFaint($_), $i), "\n";
                }
            }
        }

        # Just print that and move on if "Always continue" was
        # previously specified
        print @prompt and next if $all;

        # Add input options to prompt
        push @prompt, "Diff, Continue, Always continue, Trash Number, Open Number (d/c/a";
        for my $x ('t', 'o') {
            push @prompt, '/', coloredByIndex("$x$_", $_) for (0..$#group);
        }
        push @prompt, ")? ";
        push @prompt, "[$lastCommand] " if $defaultLastAction and $lastCommand;

        metadataDiff(undef, map { $_->{path} } @group) if $autoDiff;

        # Get input until something sticks...
        PROMPT: while (1) {
            print "\n", @prompt;
            
            my $command;
            
            # This allows for some automated processing if there are
            # temporary patterns of thousands of items that need the
            # same processing
            #if ($group[0]->{path} =~ /\/2017-2\//) {
            #    $command = "t0"
            #}
            
            # Prompt for action
            unless ($command) {
                chomp($command = lc <STDIN>);
                $command = $lastCommand if $defaultLastAction and $command eq '';
                $lastCommand = $command;
            }
            
            # something like if -l turn on $defaultLastAction and next PROMPT
            
            my $itemCount = @group;
            for (split /;/, $command) {
                if ($_ eq 'd') {
                    # Diff
                    metadataDiff(undef, map { $_->{path} } @group);
                } elsif ($_ eq 'c') {
                    # Continue
                    last PROMPT;
                } elsif ($_ eq 'a') {
                    # Always continue
                    $all = 1;
                    last PROMPT;
                } elsif (/^t(\d+)$/) {
                    # Trash Number
                    if ($1 <= $#group && $group[$1]) {
                        if ($group[$1]->{exists}) {
                            trashMedia($group[$1]->{path});
                        } else {
                            # File we're trying to trash doesn't exist, 
                            # so just remove its metadata
                            removeMd5ForPath($group[$1]->{path});
                        }

                        $group[$1] = undef;
                        $itemCount--;
                        last PROMPT if $itemCount < 2;
                    } else {
                        print "$1 is out of range [0,", $#group, "]";
                        last PROMPT;
                    }
                } elsif (/^o(\d+)$/i) {
                    # Open Number
                    if ($1 <= $#group) {
                        `open "$group[$1]->{path}"`;
                    }
                } elsif (/^m(\d+(?:,\d+)+)$/) {
                    # Merge 1,2,3,4,... into 0
                    my @matches = split ',', $1;
                    appendMetadata(map { $group[$_]->{path} } @matches);
                }
            }
            
            # Unless someone did a last PROMPT (i.e. "next group please"), restart this group
            redo DUPES;
        } # PROMPT
    } # DUPES
}

# API ==========================================================================
# Execute metadata-diff verb
sub doMetadataDiff {
    my ($excludeSidecars, @paths) = @_;

    metadataDiff($excludeSidecars, @paths);
}

# API ==========================================================================
# Execute metadata-diff verb
sub doRemoveEmpties {
    my (@globPatterns) = @_;
    
    my %dirContentsMap = ();
    traverseGlobPatterns(sub {
        my $path = rel2abs($_);
        my ($volume, $dir, $name) = splitpath($path);
        my $vd = catpath($volume, $dir, undef);
        s/[\\\/]*$// for ($path, $vd);
        push @{$dirContentsMap{$vd}}, $name;
        push @{$dirContentsMap{$path}}, '.' if -d;
    }, 1, @globPatterns);

    #for (sort keys %dirContentsMap) {
    #    my ($k, $v) = ($_, $dirContentsMap{$_});
    #    print join(';', $k, @$v), "\n";
    #}
    
    while (my ($dir, $contents) = each %dirContentsMap) {
        unless (grep { $_ ne '.' and lc ne 'md5.txt' and lc ne '.ds_store' and lc ne 'thumbs.db' } @$contents) {
            print "Trashing $dir\n";
            trashPath($dir);
        }
    }
}

# API ==========================================================================
# Execute test verb
sub doTest {
    my $filename = $ARGV[0];
    -s $filename or confess "$filename doesn't exist";
    
    # Look for a QR code
    my @results = `qrscan '$filename'`;
    print "qrscan: ", Dumper(@results) if $verbosity >= VERBOSITY_DEBUG;

    # Parse QR codes
    my $messageDate;
    for (@results) {
        /^Message:\s*(\{.*\})/
            or confess "Unexpected qrscan output: $_";
        
        my $message = decode_json($1);
        print "message: ", Dumper($message) if $verbosity >= VERBOSITY_DEBUG;
    
        if (exists $message->{date}) {
            my $date = $message->{date};
            !$messageDate or $messageDate eq $date
                or confess "Two different dates detected: $messageDate, $date";
            $messageDate = $date
        }
    }

    if ($messageDate) {
        # Get file metadata
        my $et = new Image::ExifTool;
        $et->Options(DateFormat => '%FT%TZ');
        $et = extractInfo($filename, $et);
        my $info = $et->GetInfo(qw(
            DateTimeOriginal TimeZone TimeZoneCity DaylightSavings 
            Make Model SerialNumber));
        print "$filename: ", Dumper($info) if $verbosity >= VERBOSITY_DEBUG;
    
        my $metadataDate = $info->{DateTimeOriginal};
        print "$messageDate vs $metadataDate\n" if $verbosity >= VERBOSITY_DEBUG;
    
        # The metadata date is an absolute time (the local time where
        # it was taken without any time zone information). The message
        # date is the date specified in the QR code of the image which
        # (when using the iOS app) is the full date/time of the device
        # (local time with time zone). So if we want to compare them
        # we have to just use the local time portion (and ignore the
        # time zone), assuming that the camera and the iOS device were
        # in the same time zone at the time of capture. So, remove the
        # time zone.
        $messageDate =~ s/([+-][\d:]*)$/Z/;
        my $messageTimeZone = $1;
        print "$messageDate vs $metadataDate\n" if $verbosity >= VERBOSITY_DEBUG;
    
        $messageDate = DateTime::Format::HTTP->parse_datetime($messageDate);
        $metadataDate = DateTime::Format::HTTP->parse_datetime($metadataDate);
    
        my $diff = $messageDate->subtract_datetime($metadataDate);
    
        print "$messageDate - $messageDate = ", Dumper($diff), "\n" if $verbosity >= VERBOSITY_DEBUG;
    
        my $days = ($diff->is_negative ? -1 : 1) * 
            ($diff->days + ($diff->hours + ($diff->minutes + $diff->seconds / 60) / 60) / 24);

        print <<EOM
Make            : $info->{Make}
Model           : $info->{Model}
SerialNumber    : $info->{SerialNumber}
FileDateTaken   : $metadataDate
FileTimeZone    : $info->{TimeZone}
QRDateTaken     : $messageDate
QRTimeZone      : $messageTimeZone
QR-FileDays     : $days
QR-FileHours    : @{[$days * 24]}
EOM
    }
}

# API ==========================================================================
# Execute verify-md5 verb
sub doVerifyMd5 {
    my (@globPatterns) = @_;
    
    our $all = 0;
    findMd5s(sub {
        my ($path, $expectedMd5) = @_;
        if (-e $path) {
            # File exists
            my $actualMd5 = getMd5($path)->{md5};
            if ($actualMd5 eq $expectedMd5) {
                # Hash match
                print "Verified MD5 for $path\n";
            } else {
                # Has MIS-match, needs input
                warn "ERROR: MD5 mismatch for $path ($actualMd5 != $expectedMd5)\n";
                unless ($all) {
                    while (1) {
                        print "Ignore, ignore All, Quit (i/a/q)? ";
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
        } else {
            # File doesn't exist
            # TODO: prompt to see if we should remove this via removeMd5ForPath
            warn "Missing file: $path\n";
        }
    }, @globPatterns);
}


#-------------------------------------------------------------------------------
# Call verifyOrGenerateMd5ForFile for each media file in the glob patterns
sub verifyOrGenerateMd5ForGlob {
    my ($addOnly, $omitSkipMessage, @globPatterns) = @_;

    traverseGlobPatterns(sub {
        if (-f) {
            if (/$mediaType/) {
                verifyOrGenerateMd5ForFile($addOnly, $omitSkipMessage, $_);
            } elsif (lc ne 'md5.txt' and lc ne '.ds_store' and lc ne 'thumbs.db' and !/\.(?:thm|xmp)$/i) {
                if (!$omitSkipMessage and $verbosity >= VERBOSITY_2) {
                    print colored("Skipping    MD5 for " . rel2abs($_), 'yellow'), " (unknown file)\n";
                }
            }
        }
    }, 1, @globPatterns);
}

#-------------------------------------------------------------------------------
# If the file's md5.txt file has a MD5 for the specified [path], this
# verifies it matches the current MD5.
#
# If the file's md5.txt file doesn't have a MD5 for the specified [path],
# this adds the [path]'s current MD5 to it.
sub verifyOrGenerateMd5ForFile {
    my ($addOnly, $omitSkipMessage, $path) = @_;

    $path = rel2abs($path);
    my ($md5Path, $md5Key) = getMd5PathAndKey($path);
    
    # Get file stats for the file we're evaluating to reference and/or
    # update MD5.txt
    my $stats = stat($path) 
        or die "Couldn't stat $path: $!";

    # Add stats metadata to be persisted to md5.txt
    my $actualMd5 = {
        size => $stats->size,
        mtime => $stats->mtime,
    };
    
    # Check cache from last call (this can often be called
    # repeatedly with files in same folder, so this prevents
    # unnecessary rereads)
    our ($lastMd5Path, $lastMd5Set);
    if ($lastMd5Path and $md5Path eq $lastMd5Path) {
        # Skip files whose date modified and file size haven't changed
        # TODO: unless force override if specified
        return if canMakeMd5MetadataShortcut($addOnly, $omitSkipMessage, $path, $lastMd5Set->{$md5Key}, $actualMd5);
    }
        
    # Read MD5.txt file to consult
    my ($fh, $expectedMd5Set);
    if (open($fh, '+<:crlf', $md5Path)) {
        # Read existing contents
        $expectedMd5Set = readMd5FileFromHandle($fh);
    } else {
        # File doesn't exist, open for write
        open($fh, '>', $md5Path)
            or confess "Couldn't open $md5Path: $!";
        $expectedMd5Set = {};
    }

    # Update cache
    $lastMd5Path = $md5Path;
    $lastMd5Set = $expectedMd5Set;

    # Target hash and metadata from cache and/or md5.txt
    my $expectedMd5 = $expectedMd5Set->{$md5Key};
        
    # Skip files whose date modified and file size haven't changed
    # TODO: unless force override if specified
    return if canMakeMd5MetadataShortcut($addOnly, $omitSkipMessage, $path, $expectedMd5, $actualMd5);

    # We can't skip this, so compute MD5 now
    eval {
        # TODO: consolidate opening file multiple times from stat and getMd5
        $actualMd5 = { %$actualMd5, %{getMd5($path)} };
    };
    if ($@) {
        # Can't get the MD5
        # TODO: for now, skip but we'll want something better in the future
        warn colored("UNAVAILABLE MD5 for $path with error:", 'red'), "\n\t$@";
        return;
    }
    
    # actualMd5 and expectedMd5 should now be fully populated and 
    # ready for comparison
    if (defined $expectedMd5) {
        if ($expectedMd5->{md5} eq $actualMd5->{md5}) {
            # Matches last recorded hash, nothing to do
            print colored("Verified    MD5 for $path", 'green'), "\n";

            # If the MD5 data is a full match, then we don't have anything
            # else to do. If not (probably missing or updated metadata 
            # fields), then continue on where we'll re-write md5.txt.
            return if Compare($expectedMd5, $actualMd5);
        } else {
            # Mismatch and we can update MD5, needs resolving...
            warn colored("MISMATCH OF MD5 for $path", 'red'), 
                 " [$expectedMd5->{md5} vs $actualMd5->{md5}]\n";

            # Do user action prompt
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
                    die "MD5 mismatch for $path";
                }
            }
        }
        
        # Write MD5
        print colored("UPDATING    MD5 for $path", 'magenta'), "\n";
    } else {
        # It wasn't there, it's a new file, we'll add that
        print colored("ADDING      MD5 for $path", 'blue'), "\n";
    }

    # Add/update MD5
    $expectedMd5Set->{$md5Key} = $actualMd5;

    # Update cache
    $lastMd5Path = $md5Path;
    $lastMd5Set = $expectedMd5Set;

    # Update MD5 file
    writeMd5FileToHandle($fh, $expectedMd5Set);   
}

#-------------------------------------------------------------------------------
# Check if we can shortcut based on metadata without evaluating MD5s
sub canMakeMd5MetadataShortcut {
    my ($addOnly, $omitSkipMessage, $path, $expectedMd5, $actualMd5) = @_;
    
    if (defined $expectedMd5) {
        if ($addOnly) {
            if (!$omitSkipMessage and $verbosity >= VERBOSITY_2) {
                print colored("Skipping    MD5 for $path", 'yellow'), "(add-only)\n";
            }
            return 1;
        }
    
        if (defined $expectedMd5->{size} and 
            $actualMd5->{size}  == $expectedMd5->{size} and
            defined $expectedMd5->{mtime} and 
            $actualMd5->{mtime} == $expectedMd5->{mtime}) {
            if (!$omitSkipMessage and $verbosity >= VERBOSITY_2) {
                print colored("Skipping    MD5 for $path", 'yellow'), " (same size/date-modified)\n";
            }
            return 1;
        }
    }
    
    return 0;
}

#-------------------------------------------------------------------------------
# Print all the metadata values which differ in a set of paths
sub metadataDiff {
    my ($excludeSidecars, @paths) = @_;

    # Get metadata for all files
    my @items = map { (-e) ? readMetadata($_, $excludeSidecars) : {} } @paths;

    my @tagsToSkip = qw(
        CurrentIPTCDigest DocumentID DustRemovalData
        FileInodeChangeDate FileName HistoryInstanceID
        IPTCDigest InstanceID OriginalDocumentID
        PreviewImage RawFileName ThumbnailImage);

    # Collect all the keys which whose values aren't all equal
    my %keys = ();
    for (my $i = 0; $i < @items; $i++) {
        while (my ($key, $value) = each %{$items[$i]}) {
            no warnings 'experimental::smartmatch';
            unless ($key ~~ @tagsToSkip) {
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
    }

    # Pretty print all the keys and associated values
    # which differ
    for my $key (sort keys %keys) {
        print colored("$key:", 'bold'), ' ' x (29 - length $key);
        for (my $i = 0; $i < @items; $i++) {
            my $message = $items[$i]->{$key} || coloredFaint('undef');
            print coloredByIndex($message, $i), "\n", ' ' x 30;
        }
        print "\n";
    }
}

#-------------------------------------------------------------------------------
# Work in progress...
sub appendMetadata {
    my ($target, @sources) = @_;
    
    my @properties = qw(XPKeywords Rating Subject HierarchicalSubject LastKeywordXMP Keywords);
    
    # Extract current metadata in target
    my $etTarget = extractInfo($target);
    my $infoTarget = $etTarget->GetInfo(@properties);
    print "$target: ", Dumper($infoTarget) if $verbosity >= VERBOSITY_DEBUG;
    
    my $rating = $infoTarget->{Rating};
    my $oldRating = $rating;
    
    my %keywordTypes = ();
    for (qw(XPKeywords Subject HierarchicalSubject LastKeywordXMP Keywords)) {
        my $old = $infoTarget->{$_};
        $keywordTypes{$_} = {
            OLD => $old, 
            NEW => {map { $_ => 1 } split /\s*,\s*/, ($old || '')}
        };
    }
        
    for my $source (@sources) {
        # Extract metadata in source to merge in
        my $etSource = extractInfo($source);            
        my $infoSource = $etSource->GetInfo(@properties);
        print "$source: ", Dumper($infoSource) if $verbosity >= VERBOSITY_DEBUG;
        
        # Add rating if we don't already have one
        unless (defined $rating) {
            $rating = $infoSource->{Rating};
        }
        
        # For each field, loop over each component of the source's value
        # and add it to the set of new values
        while (my ($name, $value) = each %keywordTypes) {
            for (split /\s*,\s*/, $infoSource->{$name}) {
                $value->{NEW}->{$_} = 1;
            }
        }
    }

    my $dirty = 0;
    
    # Update rating if it's changed
    if (defined $rating and (!defined $oldRating or $rating ne $oldRating)) {
        print "Rating: ", 
            defined $oldRating ? $oldRating : "(null)", 
            " -> $rating\n";
        $etTarget->SetNewValue('Rating', $rating)
            or confess "Couldn't set Rating";
        $dirty = 1;
    }
        
    while (my ($name, $value) = each %keywordTypes) {
        my $old = $value->{OLD};
        my $new = join ', ', sort keys $value->{NEW};
        if (($old || '') ne $new) {
            print "$name: ",
                defined $old ? "\"$old\"" : "(null)",
                " -> \"$new\"\n";            
            $etTarget->SetNewValue($name, $new)
                or confess "Couldn't set $name";
            $dirty = 1;
        }
    }
    
    # Write file if metadata is dirty
    if ($dirty) {
        # Compute backup path
        my $backup = "${target}_bak";
        for (my $i = 2; -s $backup; $i++) {
            $backup =~ s/_bak\d*$/_bak$i/;
        }
    
        # Make backup
        copy $target, $backup
            or confess "Couldn't copy $target to $backup: $!";

        # Update metadata in target file
        my $write = $etTarget->WriteInfo($target);
        if ($write == 1) {
            # updated
            print "Updated $target\nOriginal backed up to $backup\n";
        } elsif ($write == 2) {
            # noop
            print "$target was already up to date\n";
        } else {
            # failure
            confess "Couldn't WriteInfo for $target";
        }
    }
}

#-------------------------------------------------------------------------------
# If specified media [path] is in the right directory, returns the falsy
# empty string. If it is in the wrong directory, a short truthy error
# string for display (colored by [colorIndex]) is returned.
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






============
------------
~~~~~~~~~~~~~


# MODEL (MD5) ------------------------------------------------------------------
# For each item in each md5.txt file under [dir], invoke [callback]
# passing it full path and MD5 hash as arguments like
#      callback($absolutePath, $md5AsString)
sub findMd5s {
    my ($callback, @globPatterns) = @_;
    
    print colored(join("\n\t", "Looking for md5.txt in", @globPatterns), 'yellow'), "\n" if $verbosity >= VERBOSITY_2; 

    traverseGlobPatterns(sub {
        if (-f and lc eq 'md5.txt') {
            my $path = rel2abs($_);
            print colored("Found $path\n", 'yellow') if $verbosity >= VERBOSITY_2;
            open(my $fh, '<:crlf', $path)
                or confess "Couldn't open $path: $!";
        
            my $md5s = readMd5FileFromHandle($fh);
            
            my ($volume, $dir, undef) = splitpath($path);
            for (sort keys %$md5s) {
                $callback->(catpath($volume, $dir, $_), $md5s->{$_}->{md5});
            }
        }
    }, 1, @globPatterns);
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the path to the file containing the md5 information and the key used
# to index into the contents of that file.
sub getMd5PathAndKey {
    my ($path) = @_;

    $path = rel2abs($path);
    my ($volume, $dir, $name) = splitpath($path);
    my $md5Path = catpath($volume, $dir, 'md5.txt');
    my $md5Key = lc $name;
    
    return ($md5Path, $md5Key);
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes the cached MD5 hash for the specified path
sub removeMd5ForPath {
    my ($path) = @_;

    my ($md5Path, $md5Key) = getMd5PathAndKey($path);

    if (open(my $fh, '+<:crlf', $md5Path)) {
        my $md5s = readMd5FileFromHandle($fh);
        
        if (exists $md5s->{$md5Key}) {
            delete $md5s->{$md5Key};            
            writeMd5FileToHandle($fh, $md5s);
            
            # TODO: update the cache from the validate func?

            print colored("! Removed $md5Key from $md5Path\n", 'bright_cyan');
        } else {
            print "$md5Key didn't exist in $md5Path\n" 
                if $verbosity >= VERBOSITY_DEBUG;
        }
    } else {
        print "Couldn't open $md5Path\n"
            if $verbosity >= VERBOSITY_DEBUG;
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# TODO
sub moveMd5ForPath {
    my ($oldPath, $newPath) = @_;

    my ($oldMd5Path, $oldMd5Key) = getMd5PathAndKey($oldPath);
    my ($newMd5Path, $newMd5Key) = getMd5PathAndKey($newPath);
    
    if (open(my $oldFh, '+<:crlf', $oldMd5Path)) {
        my $oldMd5s = readMd5FileFromHandle($oldFh);
    
        if (open(my $newFh, '+<:crlf', $newMd5Path)) {
            my $newMd5s = readMd5FileFromHandle($newFh);
            
            # TODO - We have both files, so try to move the hash entry from old to new
            
        } else {
            # TODO - write single entry to new file
            my $newMd5s = { $newMd5Key => $oldMd5s }
        }   

        delete $oldMd5s->{$oldMd5Key};            
        writeMd5FileToHandle($oldFh, $oldMd5s);
    } else {
        # TODO - error
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Deserialize a md5.txt file handle into a OM
sub readMd5FileFromHandle {
    my ($fh) = @_;
    
    print "Reading     MD5.txt\n" 
        if $verbosity >= VERBOSITY_DEBUG;
    
    # If the first char is a open curly brace, treat as JSON,
    # otherwise do the older simple name: md5 format parsing
    my $useJson = 0;
    while (<$fh>) {
        if (/^\s*([^\s])/) {
            $useJson = 1 if $1 eq '{';
            last;
        }
    }
    
    seek($fh, 0, 0)
        or confess "Couldn't reset seek on file: $!";

    if ($useJson) {
        # Parse as JSON
        return decode_json(join '', <$fh>);
        # TODO: Consider validating response - do a lc on  
        # TODO: filename/md5s/whatever, and verify vs $md5pattern???
    } else {
        # Parse as simple "name: md5" text
        my %md5s = ();    
        for (<$fh>) {
            /^([^:]+):\s*($md5pattern)$/ or
                warn "unexpected line in MD5: $_";

            $md5s{lc $1} = { md5 => lc $2 };
        }        

        return \%md5s;
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Serialize OM into a md5.txt file handle
sub writeMd5FileToHandle {
    my ($fh, $md5s) = @_;
    
    print "Writing     MD5.txt\n" if $verbosity >= VERBOSITY_DEBUG;
    
    # Clear MD5 file
    seek($fh, 0, 0)
        or confess "Couldn't reset seek on file: $!";
    truncate($fh, 0)
        or confess "Couldn't truncate file: $!";

    # Update MD5 file
    my $useJson = 1;
    if ($useJson) {
        # JSON output
        print $fh JSON->new->allow_nonref->pretty->encode($md5s);
    } else {
        # Simple "name: md5" text output
        for (sort keys %$md5s) {
            print $fh lc $_, ': ', $md5s->{$_}->{md5}, "\n";
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Calculates and returns the MD5 digest of a file.
# properties:
#   md5: primary MD5 comparison (excludes volitile data from calculation)
#   full_md5: full MD5 calculation for exact match
sub getMd5 {
    my ($path, $useCache) = @_;
    
    our %md5Cache;
    my $cacheKey = rel2abs($path);
    if ($useCache) {
        my $cacheResult = $md5Cache{$cacheKey};
        return $cacheResult if defined $cacheResult;
    }
    
    open(my $fh, '<:raw', $path)
        or confess "Couldn't open $path: $!";
        
    my $fullMd5Hash = getMd5Digest($fh);

    # If the file is a backup (has some "bak" suffix), 
    # we want to consider the real extension
    my $origPath = $path;
    $origPath =~ s/[._]bak\d*$//i;

    my $partialMd5Hash = $fullMd5Hash;

    if ($origPath =~ /\.(?:jpeg|jpg)$/i) {
        # If JPEG, skip metadata which may change and only hash pixel data
        # and hash from Start of Scan [SOS] to end...

        # Read Start of Image [SOI]
        seek($fh, 0, 0)
            or confess "Failed to reset seek for $path: $!";
        read($fh, my $soiData, 2)
            or confess "Failed to read SOI from $path: $!";
        my ($soi) = unpack('n', $soiData);
        $soi == 0xffd8
            or confess "File didn't start with SOI marker: $path";

        # Read blobs until SOS
        my $tags = '';
        while (1) {
            read($fh, my $data, 4)
                or confess "Failed to read from $path at @{[tell $fh]} after $tags: $!";

            my ($tag, $size) = unpack('nn', $data);
            last if $tag == 0xffda;

            $tags .= sprintf("%04x,%04x;", $tag, $size);
            #printf("@%08x: %04x, %04x\n", tell($fh) - 4, $tag, $size);

            my $address = tell($fh) + $size - 2;
            seek($fh, $address, 0)
                or confess "Failed to seek $path to $address: $!";
        }

        $partialMd5Hash = getMd5Digest($fh);
    } #TODO: elsif ($origPath =~ /\.(tif|tiff)$/i) {
    
    my $result = {
        md5 => $partialMd5Hash,
        full_md5 => $fullMd5Hash,
    };
    
    $md5Cache{$cacheKey} = $result;
    
    return $result;
}

# MODEL (MD5) ------------------------------------------------------------------
# Get/verify/canonicalize hash from a FILEHANDLE object
sub getMd5Digest {
    my ($fh) = @_;

    my $md5 = new Digest::MD5;
    $md5->addfile($fh);
    
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$md5pattern/
        or confess "unexpected MD5: $hexdigest";

    return $hexdigest;
}

# MODEL (Metadata) -------------------------------------------------------------
# Provided a path, returns an array of sidecar files based on extension.
sub getSidecarPaths {
    my ($path) = @_;

    if ($path =~ /[._]bak\d*$/i) {
        # For backups, we don't associate related files as sidecars
        return ($path);
    } else {
        #! This proved very damaging, so finding another way
        ### Consider everything with the same base name as a sidecar.
        ### Note that this assumes a proper extension
        ##(my $query = $path) =~ s/[^.]*$/*/;
        ##return glob qq("$query");
        
        my ($base, $ext) = splitExt($path);
        my $key = uc $ext;
        
        if (exists $sidecarTypes{$key}) {
            my $types = $sidecarTypes{$key};
            if (@$types) {            
                # Base + all the sidecar extensions as a regex
                my $query = $base . '.{' . join(',', @$types) . '}';
                my @sidecars = glob qq("$query");
            
                #confess "getting sidecar for $path has \n query:   $query\n results: " . join(';', @sidecars);
                
                confess "TODO: Where we left off... currently it looks like all matches hit even if the file doesn't exist"
                
                return ($path, @sidecars);
            } else {
                # No sidecars for this type
                return ($path);   
            }
        } else {
            # Unknown file type (based on extension)
            #warn "Assuming no sidecars for unknown file type $key for $path\n";
            #return ($path);
            confess "Unknown type $key to determine sidecars for $path"; 
        }
    }
}

# MODEL (Metadata) -------------------------------------------------------------
# Read metadata as an ExifTool hash for the specified path (and any
# XMP sidecar when appropriate)
sub readMetadata {
    my ($path, $excludeSidecars) = @_;

    my $et = extractInfo($path);

    my $info = $et->GetInfo();

    unless ($excludeSidecars) {
        # If this file can't hold XMP (i.e. not JPEG or TIFF), look for
        # XMP sidecar
        # TODO: Should we exclude DNG here too?
        # TODO: How do we prevent things like FileSize from being overwritten
        #       by the XMP sidecar? read it first? exclude fields somehow (eg
        #       by "file" group)?
        #       (FileSize, FileModifyDate, FileAccessDate, FilePermissions)
        if ($path !~ /\.(jpeg|jpg|tif|tiff|xmp)$/i) {
            (my $xmpPath = $path) =~ s/[^.]*$/xmp/;
            if (-s $xmpPath) {
                $et = extractInfo($xmpPath, $et);

                $info = { %{$et->GetInfo()}, %$info };
            }
        }
    }

    #my $keys = $et->GetTagList($info);

    return $info;
}

# MODEL (Metadata) -------------------------------------------------------------
# Wrapper for Image::ExifTool::ExtractInfo + GetInfo with error handling
sub extractInfo {
    my ($path, $et) = @_;
    
    $et = new Image::ExifTool unless $et;
    
    $et->ExtractInfo($path)
        or confess "Couldn't ExtractInfo for $path: " . $et->GetValue('Error');
        
    return $et;
}

# MODEL (Path Operations) ------------------------------------------------------
# Split a [path] into ($volume, @dirs, $name)
sub deepSplitPath {
    my ($path) = @_;

    my ($volume, $dir, $name) = splitpath($path);
    my @dirs = splitdir($dir);
    pop @dirs unless $dirs[-1];

    return ($volume, @dirs, $name);
}

# MODEL (Path Operations) ------------------------------------------------------
# Splits the filename into basename and extension. (Both without a dot.)
sub splitExt {
    my ($path) = @_;
    
    my ($filename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension
    
    return ($filename, $ext);
}

# MODEL (File Operations) ------------------------------------------------------
# Unrolls globs and traverses directories recursively calling
#   $callback->($fileName, $rootDirOfSearch);
# with current directory set to $fileName's dir before calling
# and $_ set to $fileName.
sub traverseGlobPatterns {
    my ($callback, $skipTrash, @globPatterns) = @_;

    if (@globPatterns) {
        for (sort map { glob } @globPatterns) {
            if (-d) {
                traverseGlobPatternsHelper($callback, $skipTrash, $_);
            } else {
                $callback->($_, undef);
            }
        }
    } else {
        traverseGlobPatternsHelper($callback, $skipTrash, '.');
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub traverseGlobPatternsHelper {
    my ($callback, $skipTrash, $dir) = @_;
    
    $dir = rel2abs($dir);
    find({
        preprocess => $skipTrash ? \&preprocessSkipTrash : undef,
        wanted => sub {
            $callback->($_, $dir);
        }
    }, $dir);
}

# MODEL (File Operations ) -----------------------------------------------------
# 'preprocess' callback for find of File::Find which skips .Trash dirs
sub preprocessSkipTrash  {
    return grep { !-d or lc ne '.trash' } @_;
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to a .Trash subdir and removing
# its entry from the md5.txt file
sub trashPath {
    my ($path) = @_;
    #print "trashPath('$path');\n";

    my ($volume, $dir, $name) = splitpath($path);
    my $trashDir = catpath($volume, $dir, '.Trash');
    my $trashPath = catfile($trashDir, $name);

    moveFile($path, $trashPath);
    removeMd5ForPath($path);
}

# MODEL (File Operations ) -----------------------------------------------------
# Trash the specified path and any sidecars (anything with the same path
# except for extension)
sub trashMedia {
    my ($path) = @_;
    #print colored("trashMedia($path)", 'black on_white'), "\n";

    trashPath($_) for getSidecarPaths($path);
}

# MODEL (File Operations ) -----------------------------------------------------
# Move [oldPath] to [newPath] in a convinient and safe manner
# [oldPath] - original path of file
# [newPath] - desired target path for the file
sub moveFile {
    my ($oldPath, $newPath) = @_;

    # Haven't gotten to recursive merge (for dirs 'if -d') yet...
    -e $newPath
        and confess "I can't overwrite files ($oldPath > $newPath)";

    # Create parent folder if it doesn't exist
    my $newParentDir = catpath((splitpath($newPath))[0,1]);
    -d $newParentDir or make_path($newParentDir)
        or confess "Failed to make directory $newParentDir: $!";

    # Do the real move
    move($oldPath, $newPath)
        or confess "Failed to move $oldPath to $newPath: $!";

    print colored("! Moved $oldPath\n!    to $newPath\n", 'bright_cyan');
}

# MODEL (File Operations) ------------------------------------------------------
# Move the [oldPath] directory to [newPath] with merging if [newPath]
# already exists
sub moveDir {
    my ($oldPath, $newPath) = @_;
    print "moveDir('$oldPath', '$newPath');\n" if $verbosity >= VERBOSITY_DEBUG;

    if (-d $newPath) {
        # Dest dir already exists, need to move-merge

        -d $oldPath
            or confess "Can't move a non-directory to a directory ($oldPath > $newPath)";

        for my $oldChild (glob(catfile($oldPath, '*'))) {
            # BUGBUG - this doesn't seem to like curly quotes
            (my $newChild = $oldChild) =~ s/^\Q$oldPath\E/$newPath/
                or confess "$oldChild should start with $oldPath";

            if (-e $newChild and compare($newChild, $oldChild) == 0) {
                # newChild already exists and is identical to oldChild
                # so let's just remove oldChild
                print "Removing $oldChild which already exists at $newChild\n";
                #unlink $oldChild;
            } else {
                moveFile($oldChild, $newChild);
            }
        }
    } else {
        # Dest dir doesn't exist

        # Move the source to the target
        moveFile($oldPath, $newPath);
    }
}

# VIEW -------------------------------------------------------------------------
# Format a date (such as that returned by stat) into string form
sub formatDate {
    my ($sec, $min, $hour, $day, $mon, $year) = localtime $_[0];
    return sprintf '%04d-%02d-%02dT%02d:%02d:%02d',
        $year + 1900, $mon + 1, $day, $hour, $min, $sec;
}

# VIEW -------------------------------------------------------------------------
sub coloredFaint {
    my ($message) = @_;

    return colored($message, 'faint');
}

# VIEW -------------------------------------------------------------------------
# Colorizes text for diffing purposes
# [message] - Text to color
# [colorIndex] - Index for a color class
sub coloredByIndex {
    my ($message, $colorIndex) = @_;

    return colored($message, colorByIndex($colorIndex));
}

# VIEW -------------------------------------------------------------------------
# Returns a color name (usable with colored()) based on an index
# [colorIndex] - Index for a color class
sub colorByIndex {
    my ($colorIndex) = @_;

    my @colors = ('green', 'red', 'blue', 'yellow', 'magenta', 'cyan');
    return $colors[$colorIndex % scalar @colors];
}
